## Why

Existing Talos clusters have fixed Proxmox capacity and cannot burst temporary workers into AWS. AWS workers only need stateless compute; keeping all PVC-backed workloads on Proxmox removes the EBS CSI, AZ-bound volume, and cross-site Longhorn attachment paths.

## What Changes

- Keep Talos control planes, Longhorn storage nodes, GPU capacity, and all PVC-backed workloads fixed on Proxmox; add bounded AWS Auto Scaling Group workers managed by Cluster Autoscaler for opted-in stateless pods only.
- Use Talos KubeSpan for hybrid node connectivity and KubePrism for the AWS worker API path, retaining private LAN VIPs for Argo CD and on-premises clients; verify Cilium pod connectivity without requiring a public Kubernetes API endpoint.
- Retain `local-path` as dev's sole default StorageClass and Longhorn as prod's sole default StorageClass. Add no EBS CSI, `gp3` StorageClass, or persistent storage for AWS workers.
- After destroying all three current clusters, rebuild with **one OpenTofu root per cluster environment**, Proxmox and AWS modules, new Talos identities, and separate per-environment MinIO state keys. Pin a stable OpenTofu release directly; do not migrate old Terraform state or retain Terraform 1.6 as an intermediate step.
- Keep the PR plan and per-environment PR comments using the existing GitHub Environments, with apply only from `main`. Use separate, narrowly scoped static AWS IAM access keys for CI provisioning and the on-premises Cluster Autoscaler; do not reuse the MinIO backend credentials for AWS.

## Capabilities

### New Capabilities

- `hybrid-aws-burst-workers`: Fixed Proxmox storage and control planes, KubeSpan-connected stateless autoscaled AWS workers, and safe per-environment Git-managed reconciliation.

### Modified Capabilities

None. The existing `progressive-delivery` requirements do not change.

## Impact

- One OpenTofu cluster root with Proxmox and AWS modules, reused per-environment MinIO keys after successful destruction, new Talos secrets, API/network routing, and AWS scheduling. Old cluster identities and PVC data are not preserved.
- GitHub Actions PR plans/main applies, existing Doppler and GitHub Environments, separate static AWS IAM users/keys for CI and autoscaler, and CI branch-protection configuration.
- Argo CD component for Cluster Autoscaler and stateless-only scheduling policies; dev local-path and prod Longhorn remain confined to fixed Proxmox nodes.
