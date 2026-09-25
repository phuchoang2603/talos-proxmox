## 1. Destroy and Git-managed PR Plans

- [x] 1.0 Dispatch and verify destroy for argocd, dev and prod through the existing GitHub Actions workflow on `main`; old PVC data and Talos identities are not retained.
- [ ] 1.1 Verify trusted PRs produce argocd, dev and prod plans with three separately headed comments from the existing action; verify PRs cannot apply and main-only pushes/manual dispatch can apply.
- [ ] 1.2 Configure branch rules to require lint and the three plan checks; verify a failing plan blocks merge and fork PRs cannot use existing environment credentials.

## 2. Clean OpenTofu Root

- [x] 2.1 Pin stable OpenTofu in devenv and CI and verify provider/MinIO compatibility and that the PR comment action supports saved OpenTofu plans. Do not keep Terraform 1.6 as a migration checkpoint.
- [x] 2.2 Replace the destroyed old root with `terraform/cluster/` and `terraform/proxmox` and `terraform/aws` modules; reuse the emptied per-environment MinIO backend keys without state migration/import or old Talos identity preservation. Update CI/bootstrap/docs paths and verify fresh plans for all three environments before enabling main apply.

## 3. Static AWS Authentication Without MinIO Key Reuse

- [x] 3.1 Create a dedicated IAM user for CI provisioning, scope its mutation policy to the planned AWS burst infrastructure, and store its key as distinct `AWS_PROVIDER_*` values in the existing dev/prod Doppler configs; verify it cannot mutate unrelated AWS resources (account-wide Describe reads are required by AWS APIs).
- [ ] 3.2 Pass the CI key only to explicit AWS provider arguments via sensitive ephemeral OpenTofu variables while MinIO retains its existing backend credentials; verify the state, saved PR plan and PR comment do not contain the CI key.
- [ ] 3.3 Create a separate, ASG-scoped Cluster Autoscaler IAM user; bootstrap its Doppler-sourced key into a Kubernetes Secret on fixed capacity, and verify it can scale only the intended tagged worker groups without obtaining the CI key.

## 4. Hybrid Stateless AWS Workers

- [ ] 4.1 Add the AWS module for dev/prod only with capped small ASGs and AWS-specific Talos config using each newly generated cluster identity; verify argocd has no AWS resources and no keys or machine config leak into Git/logs.
- [ ] 4.2 Enable KubeSpan and discovery on fixed dev/prod nodes and AWS workers; retain private LAN VIPs for Argo CD and on-premises clients. Verify AWS-worker KubePrism API connectivity with the VIP blocked, worker readiness, and UDP 51820 peer connectivity in both environments without a public API endpoint.
- [ ] 4.3 Test Cilium pod/Service connectivity, DNS, MTU, WireGuard behavior and no AWS L2 service announcement in both dev and prod; do not require a dev-first rollout.
- [ ] 4.4 Argo-manage Cluster Autoscaler on fixed Proxmox capacity with accurate ASG zero-size templates and scoped static credentials; verify opted-in stateless dev workload scales 0→1→0 and Proxmox nodes are untouched.

## 5. Proxmox Storage and Production Rollout

- [ ] 5.1 Keep `local-path` as dev's only default and Longhorn as prod's only default, and add no EBS CSI/gp3; verify rendered environments and that PVC workloads/Longhorn components run only on Proxmox nodes.
- [ ] 5.2 Enforce AWS burst taints, explicit app opt-in and prevention of PVC/volumeClaimTemplate-bearing pods reaching AWS (including wildcard tolerations); verify such pods stay on Proxmox or Pending while `emptyDir` scratch remains disposable.
- [ ] 5.3 Validate prod API failover, cross-site networking and 0→1→0 stateless scaling with newly created Longhorn PVCs, then document safe drain/rollback of AWS workers and key rotation; verify instructions use the new root and per-env MinIO state keys.
