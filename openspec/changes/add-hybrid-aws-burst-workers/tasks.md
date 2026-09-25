## 1. Git-managed PR Lint
- [ ] 1.1 Verify PRs lint both OpenTofu roots and platform charts without state or secrets; verify only main pushes/manual dispatch can provision.
- [ ] 1.2 Require only lint checks on main and restrict dev/prod GitHub Environments to main; verify fork PRs cannot access deployment credentials.

## 2. Clean OpenTofu Root

- [x] 2.1 Pin OpenTofu 1.12.5 in devenv and CI and verify provider/MinIO compatibility.
- [x] 2.2 Use `terraform/cluster/` with `terraform/proxmox/` and `terraform/aws/` modules and per-environment MinIO backend keys. Update CI/bootstrap/docs paths and verify plans for all three environments.

## 3. GitHub OIDC Without MinIO Key Reuse

- [x] 3.1 Manage the GitHub OIDC provider and scoped CI role/policy in `terraform/identity/` local state, independent of the cluster root (account-wide Describe reads remain).
- [ ] 3.2 Pass the temporary OIDC session only to explicit AWS provider arguments via sensitive ephemeral variables while MinIO retains its existing backend credentials; verify a main-only CI run and state do not expose the session.
- [ ] 3.3 Provision a separate, ASG-scoped Cluster Autoscaler identity and bootstrap it onto fixed capacity; verify it can scale only intended worker groups without accessing the CI role.

## 4. Hybrid Stateless AWS Workers

- [ ] 4.1 Add the AWS module for dev/prod only with capped small ASGs and AWS-specific Talos config using each newly generated cluster identity; verify argocd has no AWS resources and no keys or machine config leak into Git/logs.
- [ ] 4.2 Enable KubeSpan and discovery on fixed dev/prod nodes and AWS workers; retain private LAN VIPs for Argo CD and on-premises clients. Verify AWS-worker KubePrism API connectivity with the VIP blocked, worker readiness, and UDP 51820 peer connectivity in both environments without a public API endpoint.
- [ ] 4.3 Test Cilium pod/Service connectivity, DNS, MTU, WireGuard behavior and no AWS L2 service announcement in both dev and prod; do not require a dev-first rollout.
- [ ] 4.4 Argo-manage Cluster Autoscaler on fixed Proxmox capacity with accurate ASG zero-size templates and a separate scoped identity; verify opted-in stateless dev workload scales 0→1→0 and Proxmox nodes are untouched.

## 5. Proxmox Storage and Production Rollout

- [ ] 5.1 Keep `local-path` as dev's only default and Longhorn as prod's only default, and add no EBS CSI/gp3; verify rendered environments and that PVC workloads/Longhorn components run only on Proxmox nodes.
- [ ] 5.2 Enforce AWS burst taints, explicit app opt-in and prevention of PVC/volumeClaimTemplate-bearing pods reaching AWS (including wildcard tolerations); verify such pods stay on Proxmox or Pending while `emptyDir` scratch remains disposable.
- [ ] 5.3 Validate prod API failover, cross-site networking and 0→1→0 stateless scaling with newly created Longhorn PVCs, then document safe drain/rollback of AWS workers and key rotation; verify instructions use the new root and per-env MinIO state keys.
