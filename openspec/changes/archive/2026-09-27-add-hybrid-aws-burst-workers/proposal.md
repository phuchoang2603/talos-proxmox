## Why

Existing Talos clusters have fixed Proxmox capacity and cannot burst temporary workers into AWS. AWS workers only need stateless compute; keeping all PVC-backed workloads on Proxmox removes the EBS CSI, AZ-bound volume, and cross-site Longhorn attachment paths.

## What Changes

- Keep Talos control planes, Longhorn storage nodes, GPU capacity, and all PVC-backed workloads fixed on Proxmox; add bounded AWS Auto Scaling Group workers managed by Cluster Autoscaler for opted-in stateless pods only.
- Use Talos KubeSpan for hybrid node connectivity and KubePrism for the AWS worker API path, retaining private LAN VIPs for Argo CD and on-premises clients; verify Cilium pod connectivity without requiring a public Kubernetes API endpoint.
- Retain `local-path` as dev's sole default StorageClass and Longhorn as prod's sole default StorageClass. Add no EBS CSI, `gp3` StorageClass, or persistent storage for AWS workers.
- Use one `terraform/cluster/` root with Proxmox and AWS modules and separate per-environment MinIO state keys. Give dev and prod separate managed VPCs and autoscaler IAM identities in the AWS module; manage only the GitHub OIDC CI role in the independent `terraform/identity/` root.
- Lint PRs without secrets or state access; plan and apply only from `main`. Manage the GitHub OIDC CI role in a separate local OpenTofu root; keep MinIO backend credentials separate. Provision a separate on-premises autoscaler identity before enabling autoscaling.

## Capabilities

### New Capabilities

- `hybrid-aws-burst-workers`: Fixed Proxmox storage and control planes, KubeSpan-connected stateless autoscaled AWS workers, and safe per-environment Git-managed reconciliation.

### Modified Capabilities

None.

## Impact

- One OpenTofu cluster root with Proxmox and AWS modules, separate dev/prod VPCs and autoscaler identities, per-environment MinIO keys, Talos secrets, and AWS scheduling; the independent identity root manages the CI IAM role.
- GitHub Actions PR lint/main applies, existing Doppler and main-only GitHub Environments, a dedicated GitHub OIDC CI role, and separate per-environment autoscaler identities.
- Argo CD component for Cluster Autoscaler and stateless-only scheduling policies; dev local-path and prod Longhorn remain confined to fixed Proxmox nodes.
