# GitHub Actions Automated Deployment

CI uses GitHub Actions Environments and Doppler for Talos on Proxmox. CI uses OpenTofu 1.12.6 for a clean rebuild described in `openspec/changes/add-hybrid-aws-burst-workers/`.

## Prerequisites

- [Doppler Setup](./doppler-setup.md)
- Tailscale (GitHub-hosted runners)
- GitHub repository `talos-proxmox`
- Proxmox API access
- MinIO (or S3) for OpenTofu state

**Merging this branch triggers apply for all three environments** and rebuilds their fixed Proxmox clusters from empty state. The old Talos clusters have already been destroyed; no automatic rebuild has run.

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

After **argocd** provision, CI runs `apps/bootstrap/bootstrap-argocd.sh` (Argo CD + remote cluster registration + platform app-of-apps roots). Provision **dev** and **prod** first so their `KUBECONFIG` values exist in Doppler when argocd registers remote clusters.

## AWS Burst Prerequisites

Dev/prod use the AWS **us-east-1** default VPC and one default public subnet, with an official Talos v1.13.9 amd64 AMI pinned in their `main.tfvars`. Each ASG has desired capacity zero and maximum two `t3.large` workers. Check subnet, AMI, EC2/boot-disk cost, and UDP 51820 ingress before an apply. The gp3 boot disk is disposable node storage, not an EBS CSI PV. Launch-template user data contains Talos machine configuration and is retained in restricted MinIO state; never upload saved plan files.

The separate `talos-proxmox-ci` and `talos-proxmox-autoscaler` IAM users and keys are configured in dev/prod Doppler; their write policies are recorded in `terraform/aws/iam/`. AWS Describe permissions are account-wide even though mutating permissions are project-scoped. Local read-only plans pass for argocd, dev, and prod. The autoscaler, PVC exclusion admission policy, and live KubeSpan/Cilium checks are not yet complete. This foundation keeps AWS worker ASGs at zero; do not manually scale them or opt workloads into AWS until the remaining safety checks and autoscaler work are complete.

## Hybrid Network

Keep the per-environment Kubernetes API VIP private for LAN clients and the separate Argo CD cluster. In dev and prod, Talos enables KubeSpan and discovery on fixed Proxmox nodes; AWS worker nodes must use the same cluster identity, KubeSpan, and local KubePrism (`localhost:7445`, as configured for Cilium) to reach discovered control-plane addresses. Do not expose TCP 6443 to AWS solely for joining workers. The argocd cluster does not need KubeSpan to manage dev and prod; it uses their private VIPs.

Allow outbound access to the Talos discovery service and inbound UDP 51820 on at least one side of each Proxmox-to-AWS peer connection (prefer the AWS worker). Before scheduling burst workloads, verify that AWS workers become Ready and that KubePrism reaches a control plane with the LAN VIP unreachable; test Cilium pod traffic and MTU across both sites. If this cannot work reliably, add a *private* reachable API gateway or load balancer as a separately reviewed design change.

## Step 2: GitHub Environments and Secrets

Settings → Environments: keep **`argocd`**, **`dev`**, and **`prod`** (same names as `terraform/cluster/env/`). PR plans and main applies use the existing per-environment `DOPPLER_TOKEN` and Doppler config. No `plan-*` environments or extra MinIO credentials are required. If `prod` has required reviewers, its PR plan waits for approval before posting a comment.

PR plans read OpenTofu state containing Talos cluster secrets and run PR code with the environment's credentials. Only approve plans for trusted, reviewed same-repository branches; fork PRs intentionally fail. The plan comment uses the existing `borchero/terraform-plan-comment@v2` action, with a separate header for each environment. Review what the plan reveals before using this on a public repository. Saved plan files stay on the ephemeral runner and are not uploaded as artifacts.

Settings → Rules → branch protection/ruleset for `main`: require `OpenTofu Lint`, `Platform charts and bootstrap`, `Plan (argocd)`, `Plan (dev)`, and `Plan (prod)` before merge. GitHub's required checks are repository settings, not something workflow YAML can enforce. Run a trusted PR to discover the exact check names in the GitHub UI and select those.

## Step 3: Deploy

1. **PR targeting `main`:** After lint and any existing environment approval, plans `argocd`, `dev`, and `prod` against their individual MinIO state keys and posts one plan comment per environment. No apply, Helm bootstrap, or uploaded plan artifact.
2. **Push to `main`:** Re-plans and applies all three environments using their apply environments, writes `TALOSCONFIG` / `KUBECONFIG` to Doppler, then runs bootstrap and Argo CD platform roots.
3. **Run workflow from `main` only:** Select `dev`, `prod`, or `argocd` and action **apply** or **destroy**. The job cannot run from a non-main ref.

State key: `talos-${environment}.tfstate` (does not overwrite RKE2 `dev.tfstate` / `prod.tfstate`). Backend credentials are MinIO credentials, **not** AWS IAM credentials. The AWS provider must use a separately named, scoped static AWS IAM access key from the existing dev/prod Doppler configs. Cluster Autoscaler on Proxmox will use a different ASG-scoped IAM key delivered as an in-cluster Secret. AWS workers are stateless: no EBS CSI or AWS PVCs. See the OpenSpec design.

## Destroy

Actions → Provision and Bootstrap → Run workflow on the `main` branch → environment + **destroy**. Helm is skipped; destroying nodes removes the cluster. Require approval on production environments before enabling destroy.

## Next

[Cluster Access](./cluster-access.md)
