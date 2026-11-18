## Why

The Doppler → External Secrets Operator (ESO) bridge is duplicated and tangled across the platform repo (`talos-proxmox`) and the two consumer repos (`refurbished-marketplace`, `payment-gateway-fraud-detection`):

- **The store is declared three times, inconsistently.** The platform owns a token-scoped `ClusterSecretStore/doppler`; marketplace ships its own `SecretStore/doppler` (namespaced, in `ecommerce`); payment-gateway ships its own `ClusterSecretStore/gateway-doppler`. Each consumer carries an entire `secret-store` Helm chart that redeclares the mechanism the platform already runs.
- **Tokens are provisioned inconsistently.** The platform creates `kube-system/doppler-token` from Terraform, but each consumer hand-applies its own `doppler-token` Secret (e.g. `refurbished-marketplace/infra/k8s/doppler-token.prd.secret.yaml`) out of band — untracked and prone to drift.
- **Consumers reach into the platform's Doppler project.** payment-gateway's `llm-platform` reads object-storage credentials (`OBJECT_ARTIFACTS_*`) through `platformSecretStore: doppler`, i.e. the platform's own `talos-proxmox` Doppler project. Every other payment-gateway chart reads `OBJECT_GATEWAY_*` from its `gateway-doppler` store, but `terraform/cluster/rustfs.tf` writes those keys into the `talos-proxmox` project (and under the wrong name, `OBJECT_TRAINING_*`), so today they only resolve if someone hand-copies them into the consumer project. That hand-copy is the duplicated-secret hack.

The platform should own the mechanism; consumers should own only their own `ExternalSecret`s and reference a platform-provided store by name.

## What Changes

- The platform owns one `ClusterSecretStore` per consumer Doppler project (`marketplace-doppler`, `gateway-doppler`), each scoped by `conditions.namespaces`, alongside its existing `doppler` store.
- Foundation issues a read-only `external-secrets` service token per consumer project and config, and writes each into the platform's own config as `ESO_MARKETPLACE_DOPPLER_TOKEN` / `ESO_GATEWAY_DOPPLER_TOKEN`.
- The platform root creates one `kube-system/<consumer>-doppler-token` Secret per consumer from those tokens, mirroring the existing `terraform/platform/external-secrets.tf` pattern.
- **BREAKING** Each consumer deletes its `secret-store` Helm chart, its app-of-apps entry for it, and its hand-applied `doppler-token` Secret. Consumers reference the platform-owned store by name only.
- **BREAKING** The payment-gateway object-storage credentials move into the payment-gateway Doppler project: `terraform/cluster/rustfs.tf` renames the `training` consumer to `gateway` (so the generated key becomes `OBJECT_GATEWAY_*`, matching the charts), and the secret-contract routes `OBJECT_GATEWAY_*` / `OBJECT_ARTIFACTS_*` into the consumer project. The `platformSecretStore: doppler` reach is removed; `llm-platform` reads those keys from `gateway-doppler`.
- **BREAKING** Langfuse (a consumer app) stops using platform-Dex OIDC and switches to its own built-in email/password login, removing `LANGFUSE_OIDC_CLIENT_SECRET` from both the platform Dex and the consumer entirely (no mirror). The platform `auth` component drops the `langfuse` Dex static client, the `langfuse` oauth2-proxy cookie/whitelist domains, and the `langfuse-ui` shared tunnel binding; the shared gateway's JWT DENY policy gains an `identity.unauthenticatedHosts` exemption so Langfuse serves its own login, and `llm-platform` now owns the `langfuse-ui` `TunnelBinding`.
- The one genuinely shared secret that remains is `CLICKHOUSE_GRAFANA_PASSWORD` (the platform Grafana pod resolves the datasource password from its own env, which the sidecar cannot pull cross-namespace). It stays platform-owned and Terraform-mirrored into the payment-gateway project. The `ClickHouse marts` datasource *definition* moves to the consumer `clickhouse` chart as a `grafana_datasource`-labelled ConfigMap discovered by the platform Grafana sidecar; the platform `observability` chart drops the inline datasource and adds the `data` namespace to `sidecar.datasources.searchNamespace`. The `clickhouse` chart's `passwordStores.grafana: doppler` override is dropped.
- Marketplace repoints `secretStoreRef` from `{SecretStore, doppler}` to `{ClusterSecretStore, marketplace-doppler}`. Payment-gateway keeps its store name `gateway-doppler`, so every consumer `secretStoreRef` resolves to `gateway-doppler` and no reference to the platform `doppler` store remains in either consumer repo.

## Non-goals

- Changing namespace ownership: consumer roots keep creating their own namespaces (`CreateNamespace=true`); `conditions.namespaces` only scopes which namespaces may use a store.
- Moving any application secrets (db/auth/paymentGateway) between projects. Only object-storage credentials move, and only for payment-gateway.
- Rotating existing tokens or re-provisioning live clusters as part of this change.

## Capabilities

### Modified Capabilities

- `doppler-secret-delivery`: the platform becomes the single owner of every consumer's secret store and read-only token. Consumers no longer declare stores or hand-apply tokens; they consume a platform-provided `ClusterSecretStore` scoped to their namespaces.
- `ml-object-staging`: payment-gateway's scoped object-storage credentials are delivered through the consumer's own Doppler project and store, not the platform's, removing the cross-project dependency.

## Impact

- **OpenTofu (talos-proxmox):**
  - `terraform/foundation/{main,doppler}.tf`: consumer Doppler projects, read-only ESO tokens per consumer config, and `ESO_<CONSUMER>_DOPPLER_TOKEN` written into the platform config.
  - `terraform/platform/external-secrets.tf`: one token Secret per consumer in `kube-system`.
  - `terraform/cluster/{rustfs.tf,doppler.tf,secret-contract/main.tf}`: `training`→`gateway` consumer rename and project-aware routing of object-storage keys into the payment-gateway project.
- **Argo CD components (talos-proxmox):** `apps/components/external-secrets/{templates/cluster-secret-store.yaml,values.yaml}` emit one store per consumer. `apps/components/auth` drops the Langfuse Dex client and shared SSO edge wiring (oauth2-proxy domains, shared tunnel binding) and adds `identity.unauthenticatedHosts`; `apps/components/observability` drops the inline `ClickHouse marts` datasource and widens `sidecar.datasources.searchNamespace`.
- **refurbished-marketplace:** delete `infra/charts/secret-store/`, `infra/k8s/doppler-token.prd.secret.yaml(.example)`, and the `secret-store` app-of-apps entry; repoint `secretStoreRef` in `infra/charts/{refurbished-marketplace,meilisearch}/values.yaml`.
- **payment-gateway-fraud-detection:** delete `infra/charts/secret-store/` and the `secret-store` app from `infra/argocd/app-of-apps/values*.yaml`; repoint `platformSecretStore` to `gateway-doppler` in `infra/charts/llm-platform/values.yaml` and drop the `passwordStores.grafana: doppler` override in `infra/charts/clickhouse/values.yaml`; switch Langfuse to built-in login (drop `langfuseStores.oidc`, the `langfuse-oidc` ExternalSecret and the `/oauth2/` route) and have `llm-platform` own the `langfuse-ui` `TunnelBinding`; add the `grafana_datasource` ConfigMap to the `clickhouse` chart; correct `docs/deployment/security.md`. The hand-applied `payment-gateway/doppler-token` Secret has no repo manifest and is now orphaned (manual cluster cleanup).
- **Doppler:** new keys `ESO_MARKETPLACE_DOPPLER_TOKEN`, `ESO_GATEWAY_DOPPLER_TOKEN` in the platform config; `OBJECT_GATEWAY_*` / `OBJECT_ARTIFACTS_*` and the mirrored `CLICKHOUSE_GRAFANA_PASSWORD` now written into the payment-gateway project. `LANGFUSE_OIDC_CLIENT_SECRET` is retired from both projects.
