## Context

See `proposal.md` (Why) for motivation, and `specs/declarative-platform-bootstrap/spec.md` and `specs/doppler-secret-delivery/spec.md` for the required behavior.

Current layout:
- `terraform/cluster/` builds the Proxmox VMs, Talos configuration, and AWS burst infrastructure for `argocd`, `dev`, and `prod`. State lives in a homelab MinIO S3 backend under `talos-${env}.tfstate`.
- `terraform/identity/` holds the GitHub OIDC CI role in local state.
- After apply, CI shell wrappers write `KUBECONFIG` and `TALOSCONFIG` to Doppler.
- `apps/bootstrap/*.sh` installs these with Helm or kubectl: Gateway API CRDs, Cilium in two passes (SPIRE waits for a StorageClass), Talos CCM, storage, metrics-server, and GPU components. It also copies Doppler values into Secrets and, on the argocd cluster, installs Argo CD and registers dev and prod as remote clusters.
- The central Argo CD manages External Secrets Operator (ESO), Cluster Autoscaler, the burst policy, observability, the operators, and the Cloudflare tunnel on dev and prod.

Inventory: dev has one GPU server. Prod has three GPU servers and three Longhorn nodes.

This change assumes fresh state, and the argocd environment is deleted rather than migrated.

## Goals / Non-Goals

**Goals:**

- Two independent environments, dev and prod. Each runs cluster, then platform, then its own Argo CD, with no cross-environment credentials or ordering.
- Every resource has one owner, following a fixed layering: foundation, then cluster, then platform, then the in-cluster Argo CD.
- Roots hand data to each other through Doppler. No root reads another root's state.
- The only Doppler credential inside a cluster is one read-only ESO token for that environment.

**Non-Goals:**

- A central multi-cluster Argo CD view. Each environment has its own UI.
- Automatic pod restarts on secret changes. Rotation is rare and started by a person, so restarts go through Argo CD's built-in Restart action.
- Creating the Cloudflare tunnel or the MinIO/Longhorn users in Terraform, keyless autoscaler authentication, or Argo CD SSO.
- The KubeSpan resilience fix (LAN fallback and Kubernetes discovery registry). It is tracked separately.

## Decisions

### Only dev and prod, each with its own Argo CD

The following are deleted:
- `terraform/cluster/env/argocd/`;
- every `env == "argocd"` branch in `terraform/cluster`, `terraform/proxmox`, and the AWS provider block;
- `apps/components/*/environments/argocd/`;
- `apps/argocd/roots/`;
- the argocd CI jobs;
- the argocd Doppler config and GitHub Environment.

`module.aws` becomes unconditional, and the AWS provider always uses the CI OIDC session.

Each platform root installs Argo CD in its own cluster. That Argo CD reconciles only `https://kubernetes.default.svc`. The Git repository is public, so no repository credentials are needed.

Alternative considered: keeping a hub Argo CD. Rejected because it needs a third cluster, remote-cluster registration, cross-config Doppler tokens, a Talos admin certificate handed to another cluster, and ordering between environments.

### Three roots, with Doppler as the hand-off

| Root | State | Applied by | Owns |
|---|---|---|---|
| `terraform/foundation/` | HCP `talos-proxmox` | Operator | HCP Terraform state workspaces; GitHub OIDC provider and CI role; the Doppler project and `dev`/`prod` configs; Doppler service tokens; GitHub Environment `DOPPLER_TOKEN` secrets |
| `terraform/cluster/` | HCP `talos-cluster-${env}` | CI | Proxmox, Talos, and AWS; generated credentials written with `doppler_secret` |
| `terraform/platform/` | HCP `talos-platform-${env}` | CI | Gateway API CRDs, Cilium, the ESO token Secret, the cluster health gate, Argo CD, and its root Application |

Why `platform` is a separate root: the Kubernetes and Helm providers can't be reliably configured from a kubeconfig created in the same apply, because the value is unknown at plan time on a fresh cluster. The platform root instead reads `KUBECONFIG` and `TALOSCONFIG` from Doppler through `data "doppler_secrets"` and configures its providers with `yamldecode`, so they are fully known at plan time.

For node lists, the platform root reads the same Git inventory files as the cluster root (`terraform/cluster/env/${env}/k8s_nodes.json` and `network.json`). It never reads the cluster root's state.

Alternatives considered:
- A single root with provider aliases. Rejected because plans become unreliable on a fresh cluster.
- `terraform_remote_state`. Rejected because it couples the two states and exposes everything in the cluster root's state.

### State lives in HCP Terraform with local execution

All three roots use a `cloud` block for organization `phuchoang2603` on the HCP Terraform free tier. Foundation uses the named workspace `talos-proxmox`; it inherits the organization's default execution mode, which must be set to Local first. Cluster and platform select workspaces by tag (`talos-cluster`, `talos-platform`), and CI chooses one with `TF_WORKSPACE`. Because `TF_WORKSPACE` does not create workspaces, foundation owns `talos-cluster-{dev,prod}` and `talos-platform-{dev,prod}` as `tfe_workspace` resources with `execution_mode = "local"` in `tfe_workspace_settings`. Each root's `env` variable validation rejects a `TF_WORKSPACE` naming the other environment, so a dev plan can never run against prod state.

Local execution keeps plans on the operator's machine or the CI runner, the only places that reach Proxmox and the private API VIP over the LAN or Tailscale. HCP Terraform only stores, versions, and locks state. The free tier's 500-managed-resource limit counts resources in state regardless of execution mode; all five workspaces together hold roughly 150, so adding many more nodes or components is what would approach it. The free tier also has no team management: a single owner's user token, stored in Doppler as `HCP_TERRAFORM_TOKEN`, grants access to every workspace, including foundation's. Organization tokens cannot upload state, so they are not usable here.

A single workspace for everything is not possible: each root and environment is a separate configuration with its own state, and sharing one state would make each apply destroy the others' resources. Merging roots is rejected in the next decision.

Alternatives considered:
- Keeping MinIO. Rejected because state and locking then depend on the homelab that the state describes, and backend keys had to be separated from the AWS session by passing credentials through ephemeral variables.
- Remote execution. Rejected because HCP runners cannot reach Proxmox without an agent, which the free tier does not include.

### The foundation root owns identities and tokens

Creating Doppler service tokens needs a workspace-level token, which CI's config-scoped tokens aren't. So a person applies the foundation root locally, authenticated with `doppler login`, a local AWS session, `gh auth token`, and `tofu login app.terraform.io`. It creates:

- **The four cluster and platform state workspaces**, in the Default Project with local execution.
- **`doppler_project` `talos-proxmox`**, with environments and root configs `dev` and `prod`. These already exist and still hold the operator-entered secrets, so `import` blocks adopt them. The provider manages only the project and environments, never their secret values.
- **The `dev` and `prod` GitHub Environments** (`github_repository_environment`), each with a custom deployment branch policy allowing only `main`.
- **A read/write CI service token per config,** published as the `DOPPLER_TOKEN` secret of the matching GitHub Environment (`github_actions_environment_secret`).
- **A read-only ESO service token per config,** written into that same config as `ESO_DOPPLER_TOKEN`.
- **The GitHub OIDC provider and CI role,** moved from `terraform/identity/`. Trust stays limited to the dev and prod environment subjects. The CI IAM policy additionally allows `iam:CreateAccessKey`, `iam:DeleteAccessKey`, and `iam:ListAccessKeys` on the named autoscaler users.

Operator-entered secrets are set directly in Doppler, never as Terraform variables. This keeps them out of foundation state:
- Proxmox credentials;
- the HCP Terraform token (`HCP_TERRAFORM_TOKEN`);
- Tailscale OAuth credentials;
- the Cloudflare tunnel token;
- the Longhorn backup credentials (`LONGHORN_AWS_*`, prod only).

### The cluster root writes generated credentials

The Doppler provider authenticates with CI's config-scoped `DOPPLER_TOKEN`. The root replaces the `TF_VAR_proxmox_*` mapping with `data "doppler_secrets"`, and writes these `doppler_secret` values:
- `KUBECONFIG` and `TALOSCONFIG`, used by operators and the platform root;
- `AUTOSCALER_AWS_ACCESS_KEY_ID` and `AUTOSCALER_AWS_SECRET_ACCESS_KEY`, from `aws_iam_access_key.autoscaler` (with `create_before_destroy`) in `terraform/aws/`.

### The platform root is limited to what must exist before GitOps

1. **Gateway API CRDs:** `helm_release` of `apps/components/gateway-api`, with a pinned, vendored CRD-only Helm dependency at `charts/gateway-api-crds-<version>.tgz`, following the other component wrappers. This is a proper Helm package containing chart metadata and the upstream standard CRDs, not just a compressed YAML file. Render the CRDs as ordinary chart templates so Helm manages upgrades; Helm's special `crds/` directory would install them but skip upgrades. Record the upstream release URL and checksum with the component, and pin the dependency in `Chart.yaml` and `Chart.lock`. There is no HTTP provider or apply-time download. Verify CRD establishment before Cilium starts and cover upgrades and repeat plans in later validation.
2. **Cilium:** `helm_release` of `apps/components/cilium`, with base values plus per-environment values, depending on the CRDs. Keep the release in `kube-system` and set `cilium.authentication.mutual.spire.install.namespace = kube-system` with `existingNamespace = true`. This groups the namespaced Cilium and SPIRE resources in one existing system namespace; remove the separate `cilium-spire` namespace and its script-created labels. Any additional namespace required by a chart must be handled declaratively by that chart/release, without a namespace bootstrap script. CRDs, IP pools, and L2 policies remain cluster-scoped. Cilium uses `wait = false` because SPIRE needs a StorageClass that Argo CD provides later. The agent makes nodes Ready without SPIRE.
3. **The `external-secrets-auth` namespace** and a `kubernetes_secret` holding `ESO_DOPPLER_TOKEN`. Terraform owns this namespace and Argo CD never touches it.
4. **The health gate:** check the fixed control planes and workers after Cilium. Initial provisioning creates only fixed nodes; no burst worker is required to bootstrap the platform. However, inventory arguments do not filter the Kubernetes readiness checks in the currently pinned Talos provider: `talos_cluster_health` checks all registered Kubernetes nodes. A later apply must not fail because a terminated burst worker is still registered. The gate therefore reads nodes labeled `burst.talos.dev/compute=aws`:
   - With none registered, including every fresh bring-up, `data "talos_cluster_health"` runs the full Talos, etcd, and Kubernetes checks against the inventory's control-plane and worker addresses, waiting up to 15 minutes.
   - With any registered, `data "kubernetes_nodes"` fails a postcondition unless every inventory node name is registered and Ready. The Talos and etcd checks are skipped in this case.

   Both read after Cilium, and Argo CD depends on both. Neither waits for SPIRE.
5. **Argo CD:** `helm_release` of `apps/components/argo-cd`, then `helm_release` of a small local chart `apps/argocd/bootstrap`. That chart contains the `talos-proxmox` AppProject and one root Application, `platform`, which passes `cluster=${env}` to `apps/argocd/platform`. Helm doesn't validate CRDs at plan time, which avoids the problem `kubernetes_manifest` has before the Argo CD CRDs exist.

Terraform permanently owns Cilium and Argo CD. Argo CD can't repair a broken CNI, and having a single owner avoids two tools fighting over the same release. The Argo CD values drop the hub-specific controller tuning for fan-out across many clusters.

Alternatives considered:
- Talos `inlineManifests` for Cilium or the CRDs. Rejected because it ties changes to machine config and never prunes resources.
- Letting Argo CD adopt Cilium or itself after bootstrap. Rejected because both tools would own it.

### Argo CD: one platform chart, per-environment membership

In `apps/argocd/platform`, each component declares `clusters: [dev, prod]` or a subset. The template emits one Application per enabled component, targeting the local cluster, with automated sync, `retry` with backoff, and `SkipDryRunOnMissingResource=true`. Keep the existing sync-wave approach without adding custom Application health checks. Waves order Application submission; child applications converge asynchronously. Skipping dry-run does not make a missing CRD available at apply time, so retries handle transient dependency failures. Full convergence is validated after provisioning, not as a CI completion gate.

| Wave | Component | Environments |
|---|---|---|
| -3 | `external-secrets` | dev, prod |
| -2 | `secret-stores` (one `doppler` ClusterSecretStore) | dev, prod |
| -1 | `burst-policy`, `cilium-network` (LB pools and L2 policies from per-environment values, replacing `environments/*/network.yaml`), `metrics-server` | dev, prod |
| 0 | `local-path-provisioner` | dev |
| 0 | `longhorn` (chart, storage resources, ingress, `ExternalSecret` for MinIO backups) | prod |
| 0 | `talos-ccm` (including `burst-node-gc`), `cluster-autoscaler` (with an `ExternalSecret`) | dev, prod |
| 1 | `gpu-operator`, `nvidia-dra-driver`, `argo-cd-route` (Gateway and HTTPRoute for the Argo CD UI, with the address from per-environment values) | dev, prod |
| 0–2 | existing `cnpg`, `strimzi`, `mongodb-operator`, `observability`, `cloudflare-tunnel` (with an `ExternalSecret` for its token) | dev, prod |

Argo-managed privileged namespaces use `managedNamespaceMetadata`; Cilium and SPIRE share the existing `kube-system` namespace. The `release.json` files and `apps/bootstrap/` are removed. Chart linting moves from `apps/bootstrap/validate.sh` directly into `.github/workflows/lint.yml`. Do not add a separate validation script or duplicate the chart checks in a devenv hook.

### ESO consumption

Each cluster has one `ClusterSecretStore` named `doppler`, using ESO's Doppler provider with `auth.secretRef.dopplerToken` pointing into `external-secrets-auth`. ExternalSecrets read individual keys from the environment's config and refresh every hour by default; the autoscaler's refreshes every 5 minutes. Consumers that read their secrets only at startup, Cluster Autoscaler and `cloudflared`, are restarted with Argo CD's Restart action after a rotation.

The platform-owned bootstrap authentication Secret is the sole exception to ESO delivery of Doppler-derived Kubernetes Secrets. ESO needs this credential before it can reconcile the store; ESO must not also own that Secret.

### CI calls tofu directly

`provision.yml`, for dev and prod:
1. Checkout, Doppler CLI, OpenTofu.
2. AWS OIDC. The AWS provider uses the ambient session; no backend shares the AWS credential chain any more.
3. A masked step that exports the Tailscale OAuth client and `HCP_TERRAFORM_TOKEN` (as `TF_TOKEN_app_terraform_io`) from Doppler, then Tailscale.
4. `tofu` init, plan, and apply in `terraform/cluster` with `TF_WORKSPACE=talos-cluster-${env}`.
5. The same for `terraform/platform`, with `TF_WORKSPACE=talos-platform-${env}`.

`destroy` runs the platform root first, then the cluster root. `terraform.yml` runs dev and prod in parallel, with no follow-up job. `manual.yml` offers only dev and prod. PR lint covers `terraform/foundation`, `terraform/cluster`, `terraform/platform`, and the charts. `.github/scripts/opentofu-*.sh` and helm/kubectl setup are removed.

A green provisioning run means the cluster and platform applies completed successfully, including the bootstrap health gate and installation of the root Application. CI does not wait for every child Application to become Synced and Healthy or for SPIRE's storage to become ready. Runtime validation is a separate, later phase; its checks do not become extra provisioning workflow steps. Static validation commands live directly in `lint.yml`.

## Risks / Trade-offs

- [Generated credentials are stored in state: autoscaler keys, Doppler tokens, and GitHub secrets] → State already holds Talos CAs and machine configs, so HCP Terraform organization membership and `HCP_TERRAFORM_TOKEN` stay restricted to CI and operators. All values are marked `sensitive`.
- [HCP Terraform free tier has no RBAC, so one token reads every workspace, including foundation's Doppler service tokens] → Accepted for a single-operator homelab. Keep the organization to trusted owners, give the team token an expiration, and rotate it in both Doppler configs.
- [HCP Terraform is a new external dependency for plans and state] → Local execution means an outage blocks applies but never running clusters. State versions in HCP Terraform replace MinIO bucket versioning.
- [Doppler is a hard dependency for bring-up and plans] → Running clusters keep their existing Secrets during an outage, as the spec requires. ExternalSecret status makes failures visible. Bring-up simply waits for Doppler.
- [The autoscaler can't authenticate between key replacement and its restart] → `create_before_destroy`, the 5-minute refresh, and the documented Argo CD restart keep the gap short. Cluster Autoscaler retries, so no scaling state is lost.
- [Argo CD on every cluster costs about 0.5–1 GB of memory and adds a second UI] → This is accepted in exchange for removing a whole cluster and all cross-cluster wiring. Prod's fixed capacity absorbs it.
- [Argo CD ordering: CRDs appear late, SPIRE waits for storage, Talos CCM waits for Talos-created CRDs] → Retry with backoff and `SkipDryRunOnMissingResource`; waves do not guarantee child readiness. Validate convergence later. The bootstrap health gate does not wait for SPIRE.
- [The platform plan reads Doppler values written moments earlier] → CI runs the cluster apply before the platform plan in the same job. Gateway API CRDs come from the committed chart archive.
## Migration Plan

This is fresh state only. These steps are already done:
- the three clusters are destroyed;
- the AWS CI identity and the GitHub Environments are deleted;
- the Doppler `argocd` environment, the service tokens, and the generated keys are deleted.

The `dev` and `prod` Doppler configs keep their operator-entered secrets. Remaining steps:
1. Create the HCP Terraform organization, set its default execution mode to Local, and store an owner's user token as `HCP_TERRAFORM_TOKEN` in both Doppler configs.
2. Apply `terraform/foundation/` locally.
3. Push to `main`.

The old MinIO state objects are abandoned rather than migrated.

Rollback means reverting the commit and re-provisioning from fresh state.

## Open Questions

- Refresh intervals for ExternalSecrets other than the autoscaler's. These can be tuned after the first bring-up.
