## Context

See `proposal.md` (Why) for motivation, and `specs/doppler-secret-delivery/spec.md` and `specs/ml-object-staging/spec.md` for the required behavior.

Current layout of the Doppler → ESO bridge:
- Platform (`talos-proxmox`): foundation owns the `talos-proxmox` Doppler project and issues a read-only `external-secrets` token per config, written back as `ESO_DOPPLER_TOKEN` (`terraform/foundation/doppler.tf`). The platform root creates `kube-system/doppler-token` from it (`terraform/platform/external-secrets.tf`), and `apps/components/external-secrets` renders a single token-scoped `ClusterSecretStore/doppler`.
- Marketplace: a `secret-store` chart renders `SecretStore/doppler` in `ecommerce`, authenticated by a hand-applied `ecommerce/doppler-token` (`infra/k8s/doppler-token.prd.secret.yaml`). Services reference `{SecretStore, doppler}` via `.Values.externalSecrets.secretStoreRef`.
- Payment-gateway: a `secret-store` chart renders `ClusterSecretStore/gateway-doppler` (project `payment-gateway-fraud-detection`), authenticated by a hand-applied `payment-gateway/doppler-token`. Most charts reference `gateway-doppler` through `.Values.secretStore` / `.store` / `externalSecretStore` / `passwordStores`; `llm-platform` additionally reads `OBJECT_ARTIFACTS_*` and `LANGFUSE_OIDC_CLIENT_SECRET` from the platform's `doppler` store via `platformSecretStore`, and `clickhouse` reads `CLICKHOUSE_GRAFANA_PASSWORD` from it via a `passwordStores.grafana: doppler` override.
- Object creds: `terraform/cluster/rustfs.tf` provisions MinIO users/service accounts for consumers `substrate`, `artifacts`, `training`, generating `OBJECT_<UPPER(name)>_{ACCESS_KEY_ID,SECRET_ACCESS_KEY}` and writing them, via `secret-contract`, into the `talos-proxmox` project only. The `training` consumer maps to `minio-gateway-policy.json` but yields `OBJECT_TRAINING_*`, while payment-gateway charts read `OBJECT_GATEWAY_*` — a name mismatch that only works today through manual copying into the consumer project.

## Goals / Non-Goals

**Goals:**
- One declarative owner for the secret-store mechanism: the platform.
- One `ClusterSecretStore` per Doppler project consumed in the cluster, each scoped by namespace conditions and authenticated by a read-only, single-project token owned by Terraform.
- Consumers reference a platform store by name and own only their own ExternalSecrets.
- payment-gateway object credentials delivered through the payment-gateway project, ending the cross-project reach.

**Non-Goals:**
- Changing which namespaces exist or who creates them. Consumer roots keep `CreateNamespace=true`; store `conditions.namespaces` only scopes usage.
- Moving application secrets (db/auth/paymentGateway) between projects.
- Rotation or live re-provisioning as part of this change.

## Decisions

### Platform owns one ClusterSecretStore per consumer project

`apps/components/external-secrets/templates/cluster-secret-store.yaml` becomes a `range` over a `stores` list in `values.yaml`:
- `doppler` — platform's own, token `kube-system/doppler-token`, no conditions (unchanged).
- `marketplace-doppler` — token `kube-system/marketplace-doppler-token`, `conditions.namespaces: [ecommerce]`.
- `gateway-doppler` — token `kube-system/gateway-doppler-token`, `conditions.namespaces: [payment-gateway, data, ml, llm, llm-agents]`.

Each store omits a pinned project/config, because the read-only token already scopes it to one project/config — matching the existing platform store. The `sync-wave: "1"` annotation is retained so stores apply after the operator is healthy.

The store name `gateway-doppler` is kept identical to payment-gateway's current name so its many `.Values.secretStore` / `.store` references need no change. Marketplace's store is renamed `doppler` → `marketplace-doppler` to remove the collision with the platform's own `doppler` store (two different stores named `doppler` in one cluster is the current ambiguity).

### Terraform owns every consumer token

Foundation (`terraform/foundation/{main,doppler}.tf`) gains a `consumer_projects` local and, per consumer project × config, a read-only `external-secrets` `doppler_service_token`, each written into the platform config as `ESO_MARKETPLACE_DOPPLER_TOKEN` / `ESO_GATEWAY_DOPPLER_TOKEN`. The consumer `prd` config maps to the platform `prod` env.

The platform root (`terraform/platform/external-secrets.tf`) adds a `for_each` over a map of `{ marketplace = ESO_MARKETPLACE_DOPPLER_TOKEN, gateway = ESO_GATEWAY_DOPPLER_TOKEN }` creating `kube-system/<name>-doppler-token`, each `depends_on = [data.http.apiserver_ready]`.

Foundation needs Doppler API visibility into the consumer projects (same workspace). If a plan shows the projects are not visible, that is a blocker to surface before applying.

### Object creds move into the payment-gateway project

`terraform/cluster/rustfs.tf`: rename consumer key `training` → `gateway` so the generated variable is `OBJECT_GATEWAY_*` (what the charts read); `artifacts` already yields `OBJECT_ARTIFACTS_*`.

`terraform/cluster/secret-contract/main.tf`: make the destination project a parameter instead of the hardcoded `talos-proxmox`. `terraform/cluster/doppler.tf` routes `OBJECT_GATEWAY_*`, `OBJECT_ARTIFACTS_*` and the shared `OBJECT_STORAGE_ENDPOINT/REGION` into the `payment-gateway-fraud-detection` project (config `dev`/`prd`), while platform-only keys stay in `talos-proxmox`. Simplest shape: two `secret-contract` module instances keyed by destination project.

With the keys in the consumer project, `llm-platform`'s `platformSecretStore: doppler` is repointed to `gateway-doppler` and the cross-project reach is gone.

### Shared platform/consumer secrets: eliminate ownership overlap

`platformSecretStore` and `clickhouse`'s `passwordStores.grafana` reach into the platform `doppler` store for two secrets that are not object credentials and were shared between a platform component and a consumer app. Each is resolved by moving ownership so a value lives in only one project, not by mirroring a second copy:

- `LANGFUSE_OIDC_CLIENT_SECRET` — the platform Dex served Langfuse as a static OIDC client, so the Dex server (platform) and Langfuse (consumer) had to hold the same value. Since Langfuse is a consumer app and the only non-platform console on the shared Dex, it switches to its own built-in email/password login. The secret is retired from both projects, the `langfuse` Dex static client and the oauth2-proxy/tunnel edge wiring are removed from `apps/components/auth`, and the shared gateway's JWT DENY policy gains an `identity.unauthenticatedHosts` exemption (defaulting to the langfuse host) so Langfuse can serve its own login behind the shared gateway. `llm-platform` now owns the `langfuse-ui` `TunnelBinding` that the platform `auth` chart previously provided.
- `CLICKHOUSE_GRAFANA_PASSWORD` — the platform Grafana connects to the consumer's ClickHouse as a datasource. The datasource *definition* is consumer-owned: the `clickhouse` chart ships it as a `grafana_datasource`-labelled ConfigMap that the platform Grafana sidecar discovers (the platform `observability` chart drops the inline datasource and adds the `data` namespace to `sidecar.datasources.searchNamespace`). The sidecar provisions definitions cross-namespace but resolves the `$CLICKHOUSE_GRAFANA_PASSWORD` env reference from the Grafana pod's own env, which it cannot pull cross-namespace from a Secret, so the password alone stays platform-owned and is Terraform-mirrored into the consumer project (`gateway_platform_secrets` in `terraform/cluster/doppler.tf`). This is the one value that remains in both projects, because both ends need the literal at runtime and the Grafana pod env is structurally a platform concern.

The platform consoles (Kubeflow, Grafana, Argo CD, Argo Workflows, OpenMetadata, kagent) stay on the single platform Dex: they are platform-owned components (`apps/components/*`), not consumer apps, so pointing them at a consumer Dex would invert ownership. Only Langfuse, a consumer app, is decoupled.

### Consumer-side deletions

Marketplace: delete `infra/charts/secret-store/`, `infra/k8s/doppler-token.prd.secret.yaml(.example)`, the `secret-store` app-of-apps entry; repoint `secretStoreRef` in `infra/charts/{refurbished-marketplace,meilisearch}/values.yaml` to `{ClusterSecretStore, marketplace-doppler}` (templates already read `.kind`/`.name`).

Payment-gateway: delete `infra/charts/secret-store/` and the `secret-store` app from `infra/argocd/app-of-apps/values*.yaml`; repoint `platformSecretStore` → `gateway-doppler` in `infra/charts/llm-platform/values.yaml` and drop the `passwordStores.grafana: doppler` override in `infra/charts/clickhouse/values.yaml`. The out-of-band `payment-gateway/doppler-token` Secret has no manifest under `infra/` (it was applied directly to the cluster); it is now orphaned because ESO reads the platform-owned `kube-system/gateway-doppler-token`, and deleting the live Secret is a manual cluster cleanup left to the operator.

## Risks / Trade-offs

- **Foundation project visibility.** Foundation's Doppler provider token must cover the consumer projects; otherwise the token resources fail to plan. Mitigation: confirm on the first `tofu plan`; do not apply until additions are clean.
- **Store rename in marketplace.** Existing `SecretStore/doppler` objects in `ecommerce` become orphaned until the old `secret-store` app is pruned; ESO will reconcile the new `ClusterSecretStore` once its token Secret exists. This is a deploy-ordering note, not a code risk.
- **`llm-agents` namespace.** It appears in the dev store namespace list but not prod; the platform store conditions include it so both environments resolve. Harmless superset.
