## 1. Git-managed PR Lint

- [x] 1.1 Verify PRs lint both OpenTofu roots and platform charts without state or secrets; verify only main pushes/manual dispatch can provision.
- [x] 1.2 Restrict dev/prod GitHub Environments to main and keep PR lint independent of deployment credentials, including fork PRs. No merge protection or required status checks are part of this change.

## 2. Clean OpenTofu Root

- [x] 2.1 Use compatible OpenTofu 1.12.x in devenv (currently 1.12.6) and pin CI to 1.12.5; verify provider/MinIO compatibility.
- [x] 2.2 Use `terraform/cluster/` with `terraform/proxmox/` and `terraform/aws/` modules and per-environment MinIO backend keys. Update CI/bootstrap/docs paths and verify plans for all three environments.
- [x] 2.3 Manage separate dev/prod VPCs, public subnets and routing in `terraform/aws/`; move each autoscaler IAM identity into its environment's cluster state without replacing users or keys. Verify the default VPC is unused and argocd has no AWS resources.

## 3. GitHub OIDC Without MinIO Key Reuse

- [x] 3.1 Manage the GitHub OIDC provider and scoped CI role/policy in `terraform/identity/` local state, independent of the cluster root (account-wide Describe reads remain).
- [x] 3.2 Pass the temporary OIDC session only to explicit AWS provider arguments via sensitive ephemeral variables while MinIO retains its existing backend credentials; verify a main-only CI run and state do not expose the session.
- [x] 3.3 Provision separate, ASG-scoped Cluster Autoscaler identities and bootstrap their credentials to the dev/prod clusters; verify each key authenticates as its own user, can scale only its own group, and cannot assume the CI role. Controller deployment on fixed capacity remains in 4.4.

## 4. Hybrid Stateless AWS Workers

- [x] 4.1 Add the AWS module for dev/prod only with capped small ASGs and AWS-specific Talos config using each newly generated cluster identity; verify argocd has no AWS resources and no keys or machine config leak into Git/logs.
- [x] 4.2 Enable KubeSpan and discovery on fixed dev/prod nodes and AWS workers; retain private LAN VIPs for Argo CD and on-premises clients. Verify AWS-worker KubePrism API connectivity with the VIP blocked, worker readiness, and UDP 51820 peer connectivity in both environments without a public API endpoint.
- [x] 4.3 Test Cilium pod/Service connectivity, DNS, MTU, WireGuard behavior and no AWS L2 service announcement in both dev and prod; do not require a dev-first rollout.
- [ ] 4.4 Argo-manage Cluster Autoscaler on fixed Proxmox capacity with accurate ASG zero-size templates and a separate scoped identity; verify opted-in stateless dev workload scales 0→1→0 and Proxmox nodes are untouched.

## 5. Proxmox Storage and Production Rollout

- [ ] 5.1 Keep `local-path` as dev's only default and Longhorn as prod's only default, and add no EBS CSI/gp3; verify rendered environments and that PVC workloads/Longhorn components run only on Proxmox nodes.
- [ ] 5.2 Verify AWS nodes register with a burst taint, label and AWS provider ID before scheduling; enforce explicit app opt-in and prevention of PVC/volumeClaimTemplate-bearing pods reaching AWS (including wildcard tolerations); verify such pods stay on Proxmox or Pending while `emptyDir` scratch remains disposable.
- [ ] 5.3 Validate prod API failover, cross-site networking and 0→1→0 stateless scaling with newly created Longhorn PVCs, then document safe drain/rollback of AWS workers and key rotation; verify instructions use the new root and per-env MinIO state keys.
