## Context

The motivation is in proposal.md (Why). These facts shape the design:

- **Kubeflow** is a vendored, single-namespace render: every component runs in `ml`, which is also the gateway's ML namespace. Its pipeline images use CI run tags (`run-37518086931-1`). Tenant objects live in `apps/components/kubeflow/templates` (`profile.yaml`, `training-consumer.yaml`, `training-secret.yaml`, `pipeline-config.yaml`).
- **Object storage:** `terraform/foundation/rustfs*.tf` creates three RustFS users, `substrate`, `artifacts` and `gateway`, each covering several prefixes. `gateway` is read by six gateway charts. `artifacts` is read by Kubeflow and the gateway. The keys are copied into both the `talos-proxmox` and the gateway Doppler projects.
- **RustFS STS:** RustFS 1.0.x answers `AssumeRoleWithWebIdentity` at `minio.home.phuchoang.sbs`. Its OpenID provider settings are the `RUSTFS_IDENTITY_OPENID_*` environment variables. `CLAIM_NAME` and `CLAIM_PREFIX` map a token claim value onto a policy name (`crates/iam/src/federation/mapper.rs`).
- **Service-account issuer:** the dev issuer is `https://kubernetes.default.svc.cluster.local`, which nothing outside the cluster can resolve. Its JWKS is at `https://10.69.12.11:6443/openid/v1/jwks`, behind the cluster CA.
- **Doppler:** the `talos-proxmox` dev config has 61 keys. The gateway has 56 and the marketplace 15. Of those, the externally originated ones are Cloudflare, Proxmox, Tailscale, HCP, the RustFS root, the Dex login password, `GATEWAY_INTEGRATIONS_JSON`, and the OpenTofu outputs (kubeconfig, talosconfig). Everything else is internal: database, Redis and ClickHouse passwords, salts, cookie and signing keys, CA pools, OIDC client secrets for in-cluster clients, and LLM gateway API keys.
- **ESO** chart `2.14.0` supports generators (`Password`, `ClusterGenerator`), `PushSecret`, and the `kubernetes` provider.
- **Prod** is retired. Dev was rebuilt on 2026-11-27.

## Goals / Non-Goals

**Goals:**
- **One inventory** describes every tenant, and both foundation and the platform charts read it.
- **Native mechanisms:**
  - Argo CD AppProjects
  - Kubernetes ServiceAccount identity (STS web identity, JWT auth)
  - operator-generated credentials
  - ESO generators and the `kubernetes` provider
  - Kubeflow Profiles
  - Gateway API `allowedRoutes`
  - `TunnelBinding`s
- **No credential exists in two places,** and no static object key exists anywhere.

**Non-Goals:**
- **Hard multi-tenancy,** such as vCluster or per-tenant Argo CD.
- **Upstream kustomize references for Kubeflow.**
- **Prod GCS identity.** It returns with prod, using GCP Workload Identity Federation on the same issuer.

## Decisions

### D1. One tenant inventory
`apps/components/tenants/values.yaml` holds an entry `tenants.<id>` with these fields:
- `repo`
- `namespaces`, a list of purposes, where `""` means the bare `<id>` namespace.
- `doppler`, optional: `{project, config: {dev, prod}, namespaces}`. It exists only for tenants with external secrets.
- `objectAccess`, a list of `{namespace, serviceAccount, prefixes, mode}`.
- `modelClients`, a list of `{namespace, serviceAccount, rateLimit}`.
- `langfuse`, optional: `{project, namespace}`.
- `ml`, optional: `{namespace, owner}`.

Foundation reads the file with `yamldecode(file(...))`, and the `consumer_projects` local is deleted.

Platform workloads declare their own `objectAccess` in their component values: Kubeflow, Substrate, Langfuse, Polaris and OpenMetadata. Foundation reads those through one `platform-object-access.yaml` next to the inventory, so there is one list per owner.

*Alternative:* a list in Terraform and a separate list in Helm. Rejected because the two drift.

### D2. Workload object identity
- **Issuer:** the shared `talos` module sets `KubeServiceAccountConfig.issuer` to `https://oidc-dev.phuchoang.sbs` in dev and `https://oidc.phuchoang.sbs` in prod. `KubeAuthenticationConfig` permits anonymous requests only on `/.well-known/openid-configuration` and `/openid/v1/jwks` (plus the health paths).
- **Discovery access:** the `cloudflare-tunnel` component binds `system:service-account-issuer-discovery` to `system:unauthenticated`. It publishes only those two paths with a path-regex `TunnelBinding` to `https://kubernetes.default.svc`.
- **Origin TLS:** cloudflared verifies the API server against the cluster CA, which trust-manager copies from `kube-root-ca.crt` into the tunnel's `originCaPool` Secret.
- **Substrate:** it uses the public issuer for its JWT provider and drops the pinned CA and token.
- **Effect:** the issuer is stable across rebuilds, and RustFS fetches the JWKS over public TLS.
- **RustFS:** it gets one OpenID provider: `CONFIG_URL` points at that issuer, `CLIENT_ID` is the audience `sts.rustfs`, `CLAIM_NAME=sub`, and `CLAIM_PREFIX` is empty.
- **Policies:** foundation creates one RustFS policy per declared ServiceAccount, named after its token `sub` (`system:serviceaccount:<ns>:<sa>`). The policy grants only that entry's prefixes.
- **Workloads:** each workload mounts a projected token with audience `sts.rustfs` and sets `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_ROLE_ARN` (ignored by RustFS but required by some SDKs) and `AWS_ENDPOINT_URL_STS`. The standard AWS SDK credential chain then refreshes credentials itself. Spark, Flink and Iceberg use `WebIdentityTokenFileCredentialsProvider`, and KFP uses `fromEnv: true`.
- **Removed:** every `minio_iam_user`, `minio_iam_service_account` and `OBJECT_*_ACCESS_KEY_ID`.

*Alternatives:*
- **One static key per workload:** keeps rotation, storage and copy problems. Rejected.
- **Trusting the cluster CA in RustFS:** the CA changes on every rebuild. Rejected.

*Gate:* task 1.1 proves on RustFS that a `sub` containing `:` maps to a policy, before anything else depends on it. If it fails, stop and decide with the user.

### D3. Where each secret comes from

| Kind | Source | Examples |
| --- | --- | --- |
| Externally originated | Doppler `talos-proxmox`, or the tenant project if declared | Cloudflare, Proxmox, Tailscale, HCP, RustFS root, Dex admin login, `GATEWAY_INTEGRATIONS_JSON` |
| OpenTofu outputs for operators | Doppler `talos-proxmox` | `KUBECONFIG`, `TALOSCONFIG` |
| Database credentials | CNPG: generated `<cluster>-app`, managed roles fed by ESO `Password` generator | every Postgres user |
| Kafka credentials | Strimzi `KafkaUser` | Kafka Connect, Flink |
| Other internal keys | ESO generator `ExternalSecret` in the consuming namespace | Redis and ClickHouse passwords, Langfuse salt and nextauth, cookie and signing keys, Dex client secrets |
| Internal CA pools | cert-manager `Issuer`/`Certificate` | Substrate CA pools |
| Keys protecting retained data | ESO generator, then `PushSecret` to Doppler, then read back | none in dev today |

- **Dex clients:** each in-cluster OIDC client secret (oauth2-proxy, Langfuse, OpenMetadata, RustFS console) comes from one generator `ExternalSecret` in `auth`. The client namespace receives it through a platform `kubernetes` store (see D5).
- **What Doppler keeps:** the dev `talos-proxmox` config drops to about 15 keys. The marketplace needs no Doppler project. The gateway keeps one only if `GATEWAY_INTEGRATIONS_JSON` stays externally owned.

*Alternative:* keep generating secrets in foundation with `random_password` and writing them to Doppler. Rejected, because it is the copying and sprawl being removed.

### D4. Model gateway auth with ServiceAccount tokens
- **Authentication:** agentgateway JWT authentication verifies projected tokens with audience `llm-gateway` against the in-cluster JWKS (`https://kubernetes.default.svc/openid/v1/jwks`). The issuer is the D2 issuer.
- **Authorization:** an `AgentgatewayPolicy` per `modelClients` entry matches `sub`, and its rate limit is keyed on `sub`.
- **Clients:** gateway clients (agents, RAG, benchmark, analyst UI) mount the token and send it as the bearer credential.
- **Removed:** every `LLM_GATEWAY_*_API_KEY`.

### D5. Cross-namespace delivery
For each tenant with a `langfuse` project or a catalog principal, the `tenants` chart renders:
- a `SecretStore` named `platform` in the tenant namespace, using the ESO `kubernetes` provider;
- a reader ServiceAccount in the source namespace;
- a `Role` with `resourceNames` limited to that tenant's Secrets (`langfuse-<tenant>`, `polaris-<tenant>`).

The source Secrets are ESO generator outputs in `langfuse` and `polaris`. Langfuse headless init (`LANGFUSE_INIT_*`) reads its project keys from the same Secret.

### D6. Tenants chart
For each tenant, the chart renders:
- **Namespaces:** labelled for ambient, pod security, and `platform.phuchoang.sbs/tenant=<id>`.
- **Profile:** a Kubeflow `Profile` for `ml`.
- **ResourceQuotas.**
- **Doppler store,** if declared: an ExternalSecret in `operators` that copies `ESO_<TENANT>_DOPPLER_TOKEN` out of the platform store, plus a `ClusterSecretStore` named `doppler-<id>`. That store's conditions are the tenant label plus the inventory's Doppler namespaces.
  - *Alternative:* a namespaced store per namespace, fed through a `kubernetes` provider hop. Rejected: it takes seven objects per namespace for the same boundary, because a namespaced store can't reference a token in another namespace.
- **D5 stores:** rendered only once the platform service exists (`platformServices.<name>`).
- **AppProject:** sources limited to its repo, `sourceNamespaces: [<id>]`, destinations limited to its namespaces, an empty `clusterResourceWhitelist`, and a `namespaceResourceBlacklist` covering `SecretStore`, `ResourceQuota` and `LimitRange`.
- **Root Application:** named `root`, in namespace `<id>`, pointing at `<repo>` revision `deploy/<env>`, path `infra/argocd/app-of-apps`, values `values-<env>.yaml`.

Argo CD runs with `application.namespaces: '*'`, which is the native "Applications in any namespace" feature. Each AppProject's `sourceNamespaces` is the boundary, so a tenant's child Applications live in its primary namespace and never in `argo-cd`.

The platform `doppler` `ClusterSecretStore` excludes tenant-labelled namespaces. `terraform/platform/external-secrets.tf` creates only the platform token Secret.

### D7. Namespaces, Kubeflow, shared services
- **Namespaces:**
  - platform: `kubeflow`, `kserve`, `openmetadata`, `polaris`, `langfuse`, `llm-gateway`, `models`
  - tenants: `marketplace`, `gateway`, `gateway-data`, `gateway-ml` (a Profile), `gateway-llm`
- **Kubeflow:** vendored, re-rendered from `kubeflow/manifests` `26.10.0` in multi-user mode with release image tags. It keeps the measured memory patches. Profile namespace labels come from the profile controller config. `ClusterTrainingRuntime` read access goes into an aggregate `kubeflow-edit` role. User identity comes from oauth2-proxy through the header mapping in `auth`.
- **New components:**
  - `langfuse`: upstream chart with external CNPG, ClickHouse and Redis.
  - `llm-gateway`: Gateway with tenant-label `allowedRoutes`, model backends, and JWT, rate-limit, PII and screening policies.
  - `models`: `LLMInferenceService`s and the local model cache.
  - `polaris`
- **Moved:** OpenMetadata to `openmetadata`.
- **Observability:** Grafana sidecars and vmagent select all namespaces.

### D8. Consumer repositories (each its own change)
**Gateway:**
- **Charts:** collapse to `gateway`, `gateway-data`, `gateway-ml` and `gateway-llm`.
- **Removed:** Langfuse, the gateway and models, Polaris, the `ClusterSecretStore`s and `ClusterTunnel`s, `project.yaml`, and the roots.
- **Credentials:**
  - Every password comes from CNPG or Strimzi, or from an ESO generator in the consuming namespace.
  - S3 clients use web identity.
  - Model calls use ServiceAccount tokens.

**Marketplace:**
- **Namespace:** moves to `marketplace`.
- **Credentials:** generated passwords and JWT and Meilisearch keys.
- **Doppler:** no project.
- **Removed:** `project.yaml` and the root.

## Risks / Trade-offs

- **RustFS policy names may not accept `:`.** → Gate task 1.1. If they don't, the spike checks whether `CLAIM_PREFIX` combined with a namespaced ServiceAccount naming scheme is enough. If neither works, stop.
- **The public issuer endpoint publishes only signing public keys.** → Only the two discovery paths are routed. Every other API path through that hostname returns 404 at the tunnel.
- **Generated secrets change on every rebuild.** → Intended, because dev data is wiped too. Retained-data keys use `PushSecret` (D3).
- **Clients without a web-identity provider,** such as an older ClickHouse S3 disk or OpenMetadata. → Each is listed in task 4.6. Where a client can't use web identity, the change stops and reports it instead of adding a static key.
- **Platform and tenant PRs must land together.** → Wipe dev once, after all three repositories are merged.

## Migration Plan

1. Run gate 1.1 by hand on RustFS with a dev ServiceAccount token.
2. Merge the platform PRs in task order. Lint and render pass at each step.
3. Merge the gateway and marketplace changes.
4. Delete the internal Doppler keys and the tenant projects that are no longer needed. Delete the RustFS users.
5. Destroy and re-provision dev, then verify every scenario.
6. There is no rollback. Revert and re-provision if needed.

## Open Questions

- Should `GATEWAY_INTEGRATIONS_JSON` stay externally owned? If it does, the gateway keeps a minimal Doppler project. If not, the gateway needs none. Either way the design and tasks are the same.
- Multiple Langfuse projects through the admin API when a second tenant needs Langfuse.
