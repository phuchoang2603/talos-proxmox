## 1. Platform: foundation issues consumer tokens

- [x] 1.1 In `terraform/foundation/main.tf`, add a local describing the consumer Doppler projects and their config slugs (`refurbished-marketplace`, `payment-gateway-fraud-detection`; dev + prd). Verify with `tofu validate`.
- [x] 1.2 In `terraform/foundation/doppler.tf`, add a read-only `external-secrets` `doppler_service_token` per consumer project and config, and a `doppler_secret` writing each into the platform config as `ESO_MARKETPLACE_DOPPLER_TOKEN` / `ESO_GATEWAY_DOPPLER_TOKEN` (consumer `prd` → platform `prod`). Verify `tofu plan` shows only additions, token values sensitive, and the consumer projects visible to the provider.

## 2. Platform: token Secrets and per-consumer stores

- [x] 2.1 In `terraform/platform/external-secrets.tf`, add a `for_each` creating `kube-system/marketplace-doppler-token` and `kube-system/gateway-doppler-token` from the matching `ESO_*_DOPPLER_TOKEN`, each `depends_on = [data.http.apiserver_ready]`. Verify `tofu validate` and that values never appear in plan output.
- [x] 2.2 Convert `apps/components/external-secrets/templates/cluster-secret-store.yaml` to a `range` over a `stores` list in `values.yaml`: `doppler` (unchanged), `marketplace-doppler` (`conditions.namespaces: [ecommerce]`, token `kube-system/marketplace-doppler-token`), `gateway-doppler` (`conditions.namespaces: [payment-gateway, data, ml, llm, llm-agents]`, token `kube-system/gateway-doppler-token`), each with `sync-wave: "1"`. Verify `helm lint` and that `helm template` renders three `ClusterSecretStore`s with correct conditions and token refs.

## 3. Platform: move payment-gateway object creds into its project

- [x] 3.1 In `terraform/cluster/rustfs.tf`, rename the `training` consumer to `gateway` so the generated key is `OBJECT_GATEWAY_*`. Verify `tofu validate` and that the policy file mapping (`minio-gateway-policy.json`) is unchanged.
- [x] 3.2 Make `terraform/cluster/secret-contract/main.tf` destination-project aware (add a `project` input). In `terraform/cluster/doppler.tf`, route `OBJECT_GATEWAY_*`, `OBJECT_ARTIFACTS_*`, and `OBJECT_STORAGE_ENDPOINT/REGION` into the `payment-gateway-fraud-detection` project (config `dev`/`prd`); keep platform-only keys in `talos-proxmox`. Verify `tofu validate` and that a plan writes object keys to the consumer project.
- [x] 3.3 Eliminate the shared platform/consumer secret overlap. Langfuse switches to its own built-in login, so `LANGFUSE_OIDC_CLIENT_SECRET` is retired from both projects (not mirrored) and `apps/components/auth` drops the langfuse Dex client and edge wiring. Only `CLICKHOUSE_GRAFANA_PASSWORD` stays platform-owned and Terraform-mirrored into the payment-gateway project through `gateway_platform_secrets` in `terraform/cluster/doppler.tf`, because the platform Grafana pod env needs the literal and the datasource definition now lives in the consumer `clickhouse` chart. Verify `tofu validate`.

## 4. Marketplace

- [x] 4.1 Delete `infra/charts/secret-store/` and remove the `secret-store` entry (`apps.secret-store`, releaseName `ecommerce-secret-store`) from `infra/argocd/app-of-apps/values.yaml`.
- [x] 4.2 Delete `infra/k8s/doppler-token.prd.secret.yaml` and `.example`.
- [x] 4.3 Repoint `externalSecrets.secretStoreRef` to `{kind: ClusterSecretStore, name: marketplace-doppler}` in `infra/charts/refurbished-marketplace/values.yaml` and `infra/charts/meilisearch/values.yaml`. Verify `helm template` renders every ExternalSecret against `marketplace-doppler` and no `SecretStore/doppler` remains.

## 5. Payment-gateway

- [x] 5.1 Delete `infra/charts/secret-store/` (incl. `values-dev.yaml`/`values-prod.yaml`) and remove the `secret-store` application from `infra/argocd/app-of-apps/values.yaml`, `values-dev.yaml`, `values-prod.yaml`.
- [x] 5.2 Repoint `platformSecretStore: doppler` → `gateway-doppler` in `infra/charts/llm-platform/values.yaml`, and drop the `passwordStores.grafana: doppler` override in `infra/charts/clickhouse/values.yaml` so its grafana user falls back to `gateway-doppler`. Verify `helm template` resolves every `secretStoreRef` (including the former `platformSecretStore` / `passwordStores` ones) to `gateway-doppler` with no `doppler` store left.
- [x] 5.3 Switch Langfuse to built-in email/password login: in `infra/charts/llm-platform`, drop `langfuseStores.oidc`, the `langfuse-oidc` ExternalSecret and the `/oauth2/` VirtualService route, set `AUTH_DISABLE_USERNAME_PASSWORD: "false"`, and add the `langfuse-ui` `TunnelBinding` (pointing at `istio-ingressgateway.istio-system`). Move the `ClickHouse marts` datasource definition into the `clickhouse` chart as a `grafana_datasource`-labelled ConfigMap. Verify `helm template`/`helm lint` render no OIDC wiring, a `TunnelBinding` with the correct fqdn, and a datasource ConfigMap with `password: $CLICKHOUSE_GRAFANA_PASSWORD`.
- [x] 5.4 Correct `docs/deployment/security.md` to describe the platform-owned token Secret (`kube-system/gateway-doppler-token`) and Langfuse's built-in login (no OIDC secret). The live out-of-band `payment-gateway/doppler-token` Secret has no repo manifest; it is now orphaned and is a manual cluster cleanup (flagged, not performed). Verify no `doppler-token` manifest and no `kind: SecretStore`/`secret-store` chart remain under `infra/`.

## 6. Validation

- [x] 6.1 In the talos-proxmox devenv: `tofu validate && tofu fmt` for `terraform/foundation`, `terraform/cluster`, `terraform/platform` — all pass. `tofu plan` against live infra deferred (needs approval; not run).
- [x] 6.2 `helm template apps/components/external-secrets` renders the three stores (`doppler`, `marketplace-doppler`, `gateway-doppler`) with correct conditions and token refs.
- [x] 6.3 In both consumer repos: `grep -rn "kind: SecretStore"`/`"doppler-token"`/`"secret-store"` under `infra` return nothing; `helm template` each chart resolves store references to `marketplace-doppler` (11 marketplace ExternalSecrets) / `gateway-doppler` (51 payment-gateway ExternalSecrets) only.
- [x] 6.4 `OBJECT_GATEWAY_*` / `OBJECT_ARTIFACTS_*` names match between the cluster secret-contract output and what the payment-gateway charts read.
