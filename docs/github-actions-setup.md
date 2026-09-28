# GitHub Actions Automated Deployment

CI uses GitHub Actions Environments, OpenTofu 1.12.5, and Doppler to provision the dev and prod environments: Talos on Proxmox, stateless AWS workers, and the pre-GitOps platform. Each environment's Argo CD then reconciles everything else from Git.

## Prerequisites

- [Doppler Setup](./doppler-setup.md), with the operator-entered secrets in both configs
- Tailscale (GitHub-hosted runners)
- GitHub repository `talos-proxmox`
- Proxmox API access
- An HCP Terraform organization (free tier) for OpenTofu state

A push to `main` plans and applies dev and prod in parallel. Review infrastructure changes before merging.

## Step 1: Update VM Inventory

Edit `terraform/cluster/env/{dev,prod}/k8s_nodes.json`. Shape:

```json
{
  "dev-server1": {
    "vm_id": 1111,
    "node": "pve",
    "role": "servers",
    "address": "10.69.11.11/16",
    "cpu_cores": 4,
    "cpu_type": "host",
    "memory_mb": 8192,
    "disk_size_gb": 64,
    "datastore_id": "local-lvm"
  }
}
```

`role` `servers` is control plane, `worker` is a general worker, `longhorn` is a storage worker. GPU passthrough is `pci` on any node (Proxmox host PCI IDs); those nodes boot a second Factory image with NVIDIA production extensions. The platform root reads the same file for its health gate.

Edit `terraform/cluster/env/{env}/network.json` for the Talos API VIP and the LoadBalancer range (`lb_range`). The Cilium pool and L2 announcement nodes Argo CD applies come from `apps/components/cilium-network/environments/{env}/values.yaml`; keep them in sync with `lb_range` and the inventory. Gateway addresses: Longhorn UI in `apps/components/longhorn/environments/prod/values.yaml`, Argo CD UI in `apps/components/argo-cd-route/environments/{env}/values.yaml`. Only prod has `longhorn` nodes; dev uses local-path storage.

## Step 2: Apply the foundation root

`terraform/foundation/` is applied by an operator; CI only lints it. It owns:

- the HCP Terraform state workspaces `talos-cluster-{dev,prod}` and `talos-platform-{dev,prod}` in the Default Project, all in local execution mode;
- the GitHub OIDC provider and `talos-proxmox-ci` role, trusted only for the `dev` and `prod` environment subjects, with `ci-policy.json` and `ci-iam-policy.json`;
- the Doppler project and its `dev`/`prod` environments (adopted with `import` blocks; secret values are never managed here);
- a read/write CI service token and a read-only ESO service token per config, the latter written back as `ESO_DOPPLER_TOKEN`;
- the `dev` and `prod` GitHub Environments, each allowing deployments only from `main`, with the CI token as their `DOPPLER_TOKEN` secret.

Its own state is in the HCP Terraform workspace `talos-proxmox`, which `tofu init` creates if it does not exist. Before the first init:

1. Create the free HCP Terraform organization `phuchoang2603` (or change `organization` in all three roots' `cloud` blocks and `hcp_organization` in `terraform/foundation/main.tf`).
2. In the organization's **Settings → General**, set **Default Execution Mode** to **Local**. The foundation workspace inherits it, so plans run where the Doppler, GitHub, and AWS credentials are.
3. Create a user API token for an organization owner (**Account settings → Tokens**) with an expiration, and store it as `HCP_TERRAFORM_TOKEN` in both Doppler configs. Organization tokens cannot upload state, and the free tier has no team management, so this token can read all workspaces.

```bash
cd terraform/foundation
tofu login app.terraform.io
export DOPPLER_TOKEN="$(doppler configure get token --plain)" GITHUB_TOKEN="$(gh auth token)"
# plus a local AWS session for the account
tofu init && tofu plan && tofu apply
```

The foundation state holds the Doppler service tokens; restrict HCP Terraform organization membership accordingly. GitHub's environment-scoped OIDC subject contains the environment name and immutable owner/repository IDs, not the branch; the IDs in `terraform/foundation/main.tf` must match the repository's subject. PRs receive no environment secrets.

## Step 3: Deploy

1. **PR targeting `main`:** `lint.yml` validates `terraform/foundation`, `terraform/cluster`, and `terraform/platform`, checks the vendored Gateway API CRD checksum, and lints every chart and dev/prod overlay, without state or deployment secrets.
2. **Push to `main`:** dev and prod each run, in parallel and independently:
   1. `aws-actions/configure-aws-credentials` assumes the OIDC role.
   2. The Tailscale OAuth client and `HCP_TERRAFORM_TOKEN` are read from Doppler and exported masked, the latter as `TF_TOKEN_app_terraform_io`; Tailscale connects the runner to the LAN.
   3. `tofu` init, plan, and apply for `terraform/cluster` (workspace `talos-cluster-${env}`). It writes `KUBECONFIG`, `TALOSCONFIG`, and the autoscaler keys to Doppler.
   4. `tofu` init, plan, and apply for `terraform/platform` (workspace `talos-platform-${env}`). It reads cluster access from Doppler, installs the Gateway API CRDs, Cilium, the ESO token Secret, and Argo CD with its `platform` root Application, and gates on fixed-node health.
3. **Run Manual Provision from `main` only:** Select `dev` or `prod` and action **apply** or **destroy**. The job cannot run from a non-main ref.

A green run means both applies completed. CI does not wait for every Argo CD Application to become Synced and Healthy, or for SPIRE, which needs the StorageClass Argo CD installs. Check convergence in the environment's Argo CD UI afterward. Saved plans stay on ephemeral runners and are not uploaded. No branch protection or required status checks are configured; deployment is limited to `main` by the workflow and the Environment branch policies.

## AWS Burst Prerequisites

Dev and prod each own a separate AWS **us-east-1** VPC (`10.80.0.0/16` and `10.81.0.0/16`, respectively), with one public subnet in `us-east-1d`, an internet gateway, and a default route; the AWS default VPC is unused. Their official Talos v1.13.9 amd64 AMI is pinned in `main.tfvars`. Each ASG has desired capacity zero and maximum two `m7i-flex.large` workers. Check subnet, AMI, EC2/boot-disk cost, and UDP 51820 ingress before an apply. The gp3 boot disk is disposable node storage, not an EBS CSI PV. Launch-template user data contains Talos machine configuration and is retained in the cluster's HCP Terraform state; never upload saved plan files.

The `terraform/aws/` module owns each environment's VPC, worker group, launch template, security group, and autoscaler user, policy, and access key in the matching cluster state. The access key is therefore stored in HCP Terraform state, alongside the Talos machine secrets. AWS Describe permissions remain account-wide. Operating, opting workloads into, rolling back, and rotating keys for burst capacity are covered in [AWS Burst Workers](./aws-burst-workers.md).

## Hybrid Network

Keep each environment's Kubernetes API VIP private to the LAN; CI reaches it over Tailscale. Talos enables KubeSpan and discovery on fixed Proxmox nodes; AWS worker nodes use the same cluster identity, KubeSpan, and local KubePrism (`localhost:7445`, as configured for Cilium) to reach discovered control-plane addresses. Do not expose TCP 6443 to AWS solely for joining workers.

Allow outbound access to the Talos discovery service and inbound UDP 51820 on at least one side of each Proxmox-to-AWS peer connection (prefer the AWS worker). Before scheduling burst workloads, verify that AWS workers become Ready and that KubePrism reaches a control plane with the LAN VIP unreachable; test Cilium pod traffic and MTU across both sites. If this cannot work reliably, add a *private* reachable API gateway or load balancer as a separately reviewed design change.

## Destroy

Actions → Manual Provision → Run workflow on the `main` branch → environment + **destroy**. The platform root is destroyed first, then the cluster root, which also deletes the autoscaler user and its key. Require approval on production environments before relying on destroy.

## Next

[Cluster Access](./cluster-access.md)
