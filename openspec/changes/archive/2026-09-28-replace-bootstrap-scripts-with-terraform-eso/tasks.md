## 1. Foundation Root

- [x] 1.1 Rename `terraform/identity/` to `terraform/foundation/`, keeping the OIDC provider, dev/prod-only trust, CI role, and policies. Add `iam:CreateAccessKey`, `iam:DeleteAccessKey`, and `iam:ListAccessKeys` on `talos-proxmox-autoscaler-*` to `ci-iam-policy.json`. Verify with `tofu validate` and a policy diff review.
- [x] 1.2 Add pinned `DopplerHQ/doppler` and `integrations/github` providers. Adopt the existing `talos-proxmox` project and the `dev` and `prod` environments with `import` blocks. Verify `tofu plan` shows only imports and no create, replace, or destroy of the project or environments.
- [x] 1.3 Create the `dev` and `prod` GitHub Environments with a deployment branch policy allowing only `main`. Create a read/write CI service token per config and publish each as the environment's `DOPPLER_TOKEN` secret. Verify with `gh api .../environments` that only `main` may deploy, and that the plan marks token values sensitive.
- [x] 1.4 Create a read-only ESO service token per config and write it into that config as `ESO_DOPPLER_TOKEN`. After a local apply, verify that each token can read its own config and is rejected on write and on the other config.
- [x] 1.5 Move foundation state to the HCP Terraform workspace `talos-proxmox` with a `cloud` block, and add the pinned `hashicorp/tfe` provider. Create the `talos-cluster-{dev,prod}` and `talos-platform-{dev,prod}` workspaces, tagged `talos-cluster` and `talos-platform`, with local execution. Verify `tofu validate` and, after a local apply, that all five workspaces use local execution.

## 2. Cluster Root: dev/prod Only, Generated Credentials

- [x] 2.1 Remove the argocd environment from OpenTofu:
  - delete `terraform/cluster/env/argocd/`;
  - remove every `env == "argocd"` branch in `terraform/cluster`, `terraform/proxmox`, and the AWS provider block;
  - make `module.aws` unconditional.

  Verify with `tofu validate`, and confirm `rg argocd terraform/` finds nothing.
- [x] 2.2 Add the Doppler provider to `terraform/cluster/`. Replace the `TF_VAR_proxmox_*` mapping with `data "doppler_secrets"`. Verify with a local plan authenticated only by `DOPPLER_TOKEN`, HCP Terraform credentials, and an AWS session.
- [x] 2.4 Replace the MinIO S3 backend with a `cloud` block selecting workspaces tagged `talos-cluster`, drop the `aws_provider_*` variables so the AWS provider uses the ambient session, and reject a `TF_WORKSPACE` that names the other environment. Verify `tofu validate` without credentials, and that a mismatched workspace fails variable validation.
- [x] 2.3 Write `KUBECONFIG` and `TALOSCONFIG` with `doppler_secret`. Add `aws_iam_access_key.autoscaler` with `create_before_destroy` to `terraform/aws/` and write `AUTOSCALER_AWS_*`. Verify the values appear in the environment config after apply and show as sensitive in the plan.

## 3. Platform Root

- [x] 3.1 Create `terraform/platform/` with the `doppler`, `helm`, `kubernetes`, and `talos` providers. Configure them by `yamldecode` of `KUBECONFIG` and `TALOSCONFIG` from `data "doppler_secrets"`, with a `cloud` block selecting workspaces tagged `talos-platform` and the same workspace/environment guard. Verify `tofu validate` and `tofu init -backend=false`.
- [x] 3.2 Convert `apps/components/gateway-api/` into a wrapper with a pinned `charts/gateway-api-crds-<version>.tgz` Helm dependency containing the upstream standard CRDs. Record provenance and checksum, replace `release.json` with `Chart.yaml`/`Chart.lock`, and install through `helm_release` without an HTTP provider. Render CRDs as ordinary templates so upgrades are managed. Lint/render the package in CI; later verify CRD establishment before Cilium, upgrade behavior, and a no-change re-plan.
- [x] 3.3 Install `apps/components/cilium` with `helm_release` in `kube-system` (base plus per-environment values, `wait = false`, depending on the CRDs). Set SPIRE's namespace to `kube-system` with `existingNamespace = true`, removing the separate `cilium-spire` namespace. Check rendered namespaced Cilium/SPIRE resources and RBAC references consistently use `kube-system`; any additional namespace must be chart/release-managed. Later verify fixed-node readiness, SPIRE after storage convergence, and a no-change re-plan.
- [x] 3.4 Create the `external-secrets-auth` namespace and a token Secret from `ESO_DOPPLER_TOKEN`. Verify the Secret exists and its value never appears in plan output.
- [x] 3.5 Implement the fixed-node health gate after Cilium. The pinned `talos_cluster_health` Kubernetes checks cover all registered nodes regardless of inventory arguments, so run it only while no `burst.talos.dev/compute=aws` node is registered. Otherwise, require every inventory node to be registered and Ready through a `kubernetes_nodes` postcondition, skipping the Talos/etcd checks. Later validate initial provisioning without burst workers, failure with a stopped fixed node, and success with a terminated burst node still registered.
- [x] 3.6 Install `apps/components/argo-cd` with `helm_release`, dropping the hub-specific controller tuning. Then install a new `apps/argocd/bootstrap` chart containing the AppProject and a `platform` root Application with `cluster=${env}`, targeting the local cluster. Verify the root Application exists and syncs in both environments.

## 4. Argo CD Platform Chart

- [x] 4.1 Extend `apps/argocd/platform` with per-component `clusters`, in-cluster destinations, `retry` with backoff, and `SkipDryRunOnMissingResource`, and update the schema. Remove `apps/argocd/roots/` and the component `environments/argocd/` directories. Verify `helm template` for dev and prod renders only each environment's member components.
- [x] 4.2 Add the `secret-stores` component (one `doppler` ClusterSecretStore) and move `external-secrets` to wave -3. Verify the store reports Ready in both environments.
- [x] 4.3 Add `cilium-network` (LB pools and L2 policies rendered from per-environment values) and remove `environments/*/network.yaml`. Verify the rendered resources match the previous dev and prod pools and policies, and that LoadBalancer IPs are announced after sync.
- [x] 4.4 Move `metrics-server`, `local-path-provisioner` (dev), `longhorn` (prod, with storage resources, ingress, and an `ExternalSecret` for the MinIO backup credentials), `talos-ccm`, `gpu-operator`, and `nvidia-dra-driver` into Argo components, with privileged namespaces where needed. Verify each Application is Synced and Healthy, and that each cluster has exactly one default StorageClass.
- [x] 4.5 Add `ExternalSecret`s to `cloudflare-tunnel` and `cluster-autoscaler` (5-minute refresh for the autoscaler). Verify the Secrets are created by ESO from Doppler, and that the tunnel connects and the autoscaler registers its ASG.
- [x] 4.6 Add an `argo-cd-route` component (Gateway and HTTPRoute with a per-environment address from the Cilium pool). Verify the Argo CD UI is reachable on each environment's address.
- [x] 4.7 Delete `apps/bootstrap/` and the `release.json` files, and move chart linting directly into `.github/workflows/lint.yml`, without a separate validation script or duplicate devenv chart hook. Verify `rg 'bootstrap.sh|validate.sh|release.json|run.sh'` finds no remaining references outside OpenSpec changes.

## 5. CI

- [x] 5.1 Rewrite `provision.yml`:
  - AWS OIDC for the AWS provider;
  - a masked export of Doppler's `HCP_TERRAFORM_TOKEN` as `TF_TOKEN_app_terraform_io`;
  - direct `tofu` init, plan, and apply for the cluster root, then the platform root, each selecting its workspace with `TF_WORKSPACE`, with destroy in reverse order;
  - no helm or kubectl setup.
  - finish successfully when both applies complete; do not add a wait for all Argo CD Applications or SPIRE.

  Verify with actionlint and review that no repository script is invoked.
- [x] 5.2 Make `terraform.yml` run only dev and prod in parallel, and `manual.yml` offer only dev and prod. Delete `.github/scripts/opentofu-ci.sh` and `opentofu-with-doppler.sh`. Verify the workflow graph has no argocd job.
- [x] 5.3 Put validation commands directly in `lint.yml`: lint `terraform/foundation`, `terraform/cluster`, and `terraform/platform`, plus all charts and dev/prod overlays, including the vendored Gateway API chart. Verify a PR run passes without state or secrets.

## 6. Fresh-State Validation and Docs

Runtime checks described in earlier tasks are acceptance checks for this later validation phase, not additional provisioning CI gates. First wait for provisioning CI to be green; then validate full platform convergence separately.

- [x] 6.1 Create the HCP Terraform organization with Local default execution, store `HCP_TERRAFORM_TOKEN` in both Doppler configs, apply the foundation root locally, and push to `main`. Wait for successful cluster and platform applies for dev and prod independently. After CI is green, separately verify every Argo CD Application is Synced and Healthy and SPIRE is ready without manual provisioning steps.
- [x] 6.4 Update `README.md`, `docs/doppler-setup.md`, `docs/github-actions-setup.md`, `docs/cluster-access.md`, and `docs/aws-burst-workers.md`: the two environments, three roots, per-cluster Argo CD, the Doppler key layout, ESO consumption, and Terraform-based key rotation. Verify the docs contain no references to the argocd environment, removed scripts, or `DOPPLER_READ_TOKEN`.

### Waived validation

The operator waived tasks 6.2 and 6.3 on 2026-09-28. They are not required for completion or archival of this change and are not recorded as executed or passed. The corresponding behavioral requirements remain in the specs.

- 6.2 Secret behavior (waived):
  - rotate the autoscaler key with `tofu apply -replace` plus an Argo CD restart, and confirm the autoscaler registers the ASG;
  - change the Cloudflare token in Doppler, and confirm the Secret updates and the restarted tunnel connects;
  - block Doppler egress from a cluster, and confirm Secrets are retained and ExternalSecrets report not ready.
- 6.3 Independence (waived):
  - destroy and rebuild dev while prod's Argo CD stays Synced;
  - confirm neither cluster holds the other's credentials;
  - confirm CI logs and plans show no secret values;
  - re-run dev AWS 0→1→0 burst scaling.
