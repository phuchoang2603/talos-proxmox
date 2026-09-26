# GitHub Actions Automated Deployment

CI uses GitHub Actions Environments, OpenTofu 1.12.5, and Doppler to provision Talos on Proxmox and stateless AWS workers in dev/prod.

## Prerequisites

- [Doppler Setup](./doppler-setup.md)
- Tailscale (GitHub-hosted runners)
- GitHub repository `talos-proxmox`
- Proxmox API access
- MinIO (or S3) for OpenTofu state

A push to `main` plans and applies all three cluster environments. Review infrastructure changes before merging.

## Step 1: Update VM Inventory

Edit `terraform/cluster/env/{dev,prod,argocd}/k8s_nodes.json`. Shape:

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

`role` `servers` is control plane, `worker` is a general worker, `longhorn` is a storage worker. GPU passthrough is `pci` on any node (Proxmox host PCI IDs); those nodes boot a second Factory image with NVIDIA production extensions.

Edit `terraform/cluster/env/{env}/network.json` for the Talos API VIP and Cilium LoadBalancer pool (`lb_range`). Longhorn Gateway LAN IP: `longhorn-ingress.yaml` on prod. Argo ingress is argocd-only (`env/argocd/argo-ingress.yaml`). **dev** and **argocd** have no `longhorn` nodes (local-path storage).

On a push to `main`, dev and prod provision and bootstrap in parallel. The argocd job runs only after both succeed; it bootstraps Argo CD, registers the two clusters using their kubeconfigs from Doppler, and applies the platform roots. Manual dispatch provisions only the selected environment; when selecting argocd, provision dev and prod first if their kubeconfigs are not available in Doppler.

## AWS Burst Prerequisites

Dev and prod each own a separate AWS **us-east-1** VPC (`10.80.0.0/16` and `10.81.0.0/16`, respectively), with one public subnet in `us-east-1d`, an internet gateway, and a default route; the AWS default VPC is unused. Their official Talos v1.13.9 amd64 AMI is pinned in `main.tfvars`. Each ASG has desired capacity zero and maximum two `m7i-flex.large` workers. Check subnet, AMI, EC2/boot-disk cost, and UDP 51820 ingress before an apply. The gp3 boot disk is disposable node storage, not an EBS CSI PV. Launch-template user data contains Talos machine configuration and is retained in restricted MinIO state; never upload saved plan files.
The GitHub OIDC provider and CI role live in independent local state at `terraform/identity/`. Its infrastructure and IAM-delegation policies are `ci-policy.json` and `ci-iam-policy.json`; CI can manage project-tagged network resources and named autoscaler IAM identities. The `terraform/aws/` module owns each environment's VPC, worker group, launch template, security group, autoscaler user and policy in the matching MinIO cluster state. Neither root reads the other's state. AWS Describe permissions remain account-wide. Autoscaler access keys live only in the matching Doppler configs as `AUTOSCALER_AWS_ACCESS_KEY_ID` and `AUTOSCALER_AWS_SECRET_ACCESS_KEY`, not in Terraform state; bootstrap copies them into the corresponding cluster namespace. Operating, opting workloads into, rolling back, and rotating keys for burst capacity are covered in [AWS Burst Workers](./aws-burst-workers.md).
## Hybrid Network

Keep the per-environment Kubernetes API VIP private for LAN clients and the separate Argo CD cluster. In dev and prod, Talos enables KubeSpan and discovery on fixed Proxmox nodes; AWS worker nodes must use the same cluster identity, KubeSpan, and local KubePrism (`localhost:7445`, as configured for Cilium) to reach discovered control-plane addresses. Do not expose TCP 6443 to AWS solely for joining workers. The argocd cluster does not need KubeSpan to manage dev and prod; it uses their private VIPs.

Allow outbound access to the Talos discovery service and inbound UDP 51820 on at least one side of each Proxmox-to-AWS peer connection (prefer the AWS worker). Before scheduling burst workloads, verify that AWS workers become Ready and that KubePrism reaches a control plane with the LAN VIP unreachable; test Cilium pod traffic and MTU across both sites. If this cannot work reliably, add a *private* reachable API gateway or load balancer as a separately reviewed design change.

## Step 2: GitHub Environments and Secrets

Settings → Environments: keep **`argocd`**, **`dev`**, and **`prod`**. `dev` and `prod` allow deployments from `main` only: GitHub's environment-scoped OIDC subject contains the environment name and immutable owner/repository IDs, not the branch. The IDs in `terraform/identity/main.tf` must match the repository's GitHub OIDC subject. Each environment keeps its existing `DOPPLER_TOKEN` for MinIO, Proxmox, and bootstrap. PRs receive no environment secrets.

Manage the GitHub OIDC provider and `talos-proxmox-ci` role/policies locally with `cd terraform/identity && tofu init && tofu plan && tofu apply`. This root uses gitignored local state; keep that state and a secure backup. In the dev/prod jobs, `id-token: write` lets `aws-actions/configure-aws-credentials` exchange a GitHub OIDC token for a short-lived AWS role session. The workflow passes the session key, secret, and token through sensitive ephemeral OpenTofu variables to the cluster AWS provider. Doppler supplies separate `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` values only for the MinIO S3 backend; the wrapper clears the AWS session token before calling OpenTofu so it cannot reach MinIO. Argocd does not assume the AWS role. Saved plans stay on ephemeral runners and are not uploaded.

PRs run the three lint jobs without deployment credentials. No branch protection or required status checks are configured; deployment remains limited to `main` by the workflow and the dev/prod Environment branch policies.

## Step 3: Deploy

1. **PR targeting `main`:** Lints the OpenTofu roots and platform charts without state access or deployment secrets.
2. **Push to `main`:** Plans and applies all three environments, assumes the OIDC role for dev/prod, writes `TALOSCONFIG` / `KUBECONFIG` to Doppler, then runs bootstrap and Argo CD platform roots.
3. **Run Manual Provision from `main` only:** Select `dev`, `prod`, or `argocd` and action **apply** or **destroy**. The job cannot run from a non-main ref.

Cluster state key: `talos-${environment}.tfstate`. The on-premises autoscaler uses its own ASG-scoped identity, not the CI role or MinIO credentials. AWS workers are stateless: no EBS CSI or AWS PVCs. Cross-site networking, provider IDs, PVC admission, and 0→1→0 autoscaling were verified in dev and prod on September 25–26, 2026; see [AWS Burst Workers](./aws-burst-workers.md).

## Destroy
Actions → Manual Provision → Run workflow on the `main` branch → environment + **destroy**. Helm is skipped. The AWS module protects its autoscaler user from accidental deletion; a full cluster destroy must explicitly handle that identity and its out-of-band access key in a separately reviewed change. Require approval on production environments before enabling destroy.

## Next

[Cluster Access](./cluster-access.md)
