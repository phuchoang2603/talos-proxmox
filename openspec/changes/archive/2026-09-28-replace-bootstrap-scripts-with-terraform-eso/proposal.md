## Why

Cluster bring-up depends on imperative scripts. `apps/bootstrap/*.sh` installs Helm releases, copies Doppler values into Kubernetes Secrets with kubectl, and registers remote clusters in a separate argocd cluster. The CI wrappers push kubeconfigs back into Doppler with the CLI. Some secrets, such as the autoscaler access keys, are created by hand. The central argocd cluster adds a third environment, cross-cluster credentials, and ordering between environments.

Rebuilding from fresh state is the moment to make dev and prod self-contained, with every piece owned by exactly one declarative tool.

## What Changes

- **BREAKING** Remove the `argocd` environment entirely: its inventory, tfvars, and Talos cluster; CI jobs; Doppler config and GitHub Environment; component environment overrides; and the remote cluster registration. Only `dev` and `prod` remain.
- **BREAKING** Each environment runs its own Argo CD, which manages only its own cluster from the shared Git platform definition.
- **BREAKING** Remove `apps/bootstrap/` (all scripts) and the `release.json` files that exist only for it. Remove `.github/scripts/opentofu-ci.sh` and `opentofu-with-doppler.sh`. CI runs `tofu` directly.
- **BREAKING** Organize infrastructure into three OpenTofu roots, provisioned from fresh state:
  - `terraform/foundation/`: applied by a person. It replaces `terraform/identity/` and owns the HCP Terraform state workspaces, the GitHub OIDC CI role, the Doppler project, the `dev` and `prod` configs, the service tokens, and the main-only `dev` and `prod` GitHub Environments with their `DOPPLER_TOKEN` secrets.
  - `terraform/cluster/`: per environment, run in CI. It owns Proxmox, Talos, and AWS resources, and writes every credential it generates into Doppler through the Doppler provider.
  - `terraform/platform/`: new, per environment, run in CI. It reads cluster access from Doppler and installs only what must run before GitOps: Gateway API CRDs, Cilium, ESO's Doppler token Secret, and Argo CD with its root Application. It also gates on cluster health.
- Make Doppler the only secret hand-off. Terraform writes generated secrets to Doppler: kubeconfig, talosconfig, autoscaler IAM access keys, and ESO read tokens. People enter only externally issued secrets. Clusters read secrets only through an External Secrets Operator `ClusterSecretStore` backed by their own Doppler config.
- Move every other in-cluster component into each cluster's Argo CD with per-cluster enablement:
  - Talos CCM, Longhorn with its storage and ingress resources, local-path, metrics-server, the GPU operator and DRA driver;
  - Cilium network resources, External Secrets and its store, and the Argo CD UI route.
- Components that need secrets get them from `ExternalSecret`s that read Doppler directly: the Cloudflare tunnel token, Longhorn MinIO credentials, and autoscaler AWS keys.
- Vendor Gateway API CRDs as a pinned Helm `.tgz` dependency, matching other components, with no HTTP provider or runtime manifest download. Group Cilium and SPIRE's namespaced resources in `kube-system`.
- CI succeeds when the cluster and platform applies complete; full Argo CD convergence is validated afterward. Static validation lives directly in `.github/workflows/lint.yml`.
- The platform-owned ESO bootstrap authentication Secret is the sole exception to ESO delivery of Doppler-derived Kubernetes Secrets.
- **BREAKING** Move all OpenTofu state from the MinIO S3 backend and foundation's local state to HCP Terraform (free tier) through `cloud` blocks. Workspaces use local execution, so plans still run on the operator's machine or CI runner, which can reach Proxmox; HCP Terraform only stores and locks state.
- Create the autoscaler IAM access keys in Terraform (`aws_iam_access_key`). This deliberately stores them in HCP Terraform state, which already holds Talos machine secrets. It replaces manual key creation and the keys-never-in-state rule.

## Capabilities

### New Capabilities

- `declarative-platform-bootstrap`: Self-contained dev and prod environments reach a fully synced platform from fresh state using layered OpenTofu roots and an in-cluster Argo CD, with exactly one declarative owner per component and no imperative bootstrap scripts.
- `doppler-secret-delivery`: Doppler is the single source for secrets. Terraform writes generated credentials to it, and each cluster consumes only its own environment's secrets through ESO with one read-only bootstrap token.

### Modified Capabilities

- `hybrid-aws-burst-workers`: state moves from per-environment MinIO keys to per-environment HCP Terraform workspaces, and the separate state credential becomes the HCP Terraform token instead of MinIO keys. Separate CI and autoscaler credentials, main-only applies, and no plaintext secrets in Git or CI logs are unchanged. Its references to "the separate Argo CD cluster" were corrected when `add-hybrid-aws-burst-workers` was archived.

## Impact

- **OpenTofu:**
  - `terraform/identity/` becomes `terraform/foundation/`, adding the `DopplerHQ/doppler`, `integrations/github`, and `hashicorp/tfe` providers.
  - `terraform/cluster/` adds the Doppler provider and `aws_iam_access_key`, and removes `env/argocd/` and every `env == "argocd"` branch.
  - A new `terraform/platform/` root uses the `doppler`, `helm`, `kubernetes`, and `talos` providers.
  - HCP Terraform workspaces `talos-proxmox` (foundation), `talos-cluster-{dev,prod}`, and `talos-platform-{dev,prod}` replace the MinIO keys and local state. All state starts fresh.
- **Doppler:**
  - The `argocd` config and `DOPPLER_READ_TOKEN` are removed.
  - `ESO_DOPPLER_TOKEN` and `AUTOSCALER_AWS_*` are now written by Terraform.
  - `HCP_TERRAFORM_TOKEN` is added for state access; the MinIO backend keys are no longer used by OpenTofu.
- **Argo CD:**
  - The platform chart gains per-cluster enablement and targets only its own cluster.
  - New components: `talos-ccm`, `longhorn`, `local-path-provisioner`, `metrics-server`, `gpu-operator`, `nvidia-dra-driver`, `cilium-network`, `secret-stores`, and `argo-cd-route`.
  - `apps/argocd/roots/` is replaced by one bootstrap root per cluster.
- **CI:** `provision.yml` runs `tofu` for the cluster and platform roots and no longer needs helm, kubectl, or repository scripts. `terraform.yml` and `manual.yml` target only dev and prod. PR lint covers all three roots.
- **Docs:** `README.md`, `docs/doppler-setup.md`, `docs/github-actions-setup.md`, `docs/cluster-access.md`, and `docs/aws-burst-workers.md`.
