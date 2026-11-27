## Why

The platform and its two consumers share namespaces, cluster-scoped objects and credentials with no clear owner.

- **Namespaces:** Kubeflow, KServe and OpenMetadata run inside the gateway's `ml` and `data` namespaces.
- **Cluster-scoped objects:** the gateway creates nine `ClusterSecretStore`s, `ClusterTunnel`s and `ClusterRole`s. It also installs Polaris, Langfuse, the LLM gateway and shared model serving itself.
- **Argo CD:** the marketplace AppProject allows every cluster-scoped kind.
- **Object storage:** RustFS has three static users. One `gateway` key is shared by six gateway charts, and one `artifacts` key is shared by the platform and the gateway.
- **Doppler:** it holds about 130 secrets across three projects. About 90% of them are internal passwords, salts, signing keys and API keys that never need to leave the cluster, plus copies OpenTofu makes between projects.
- **Manual bootstrap:** each consumer needs a hand-applied namespace, Doppler token, AppProject and root.

Dev was just rebuilt from scratch, so this is the moment to redraw the boundary with native mechanisms and no migration.

## What Changes

- **BREAKING** The platform declares each consumer as a tenant from one inventory. That covers its namespaces, its AppProject and its root Application, plus a Doppler store only if the tenant has external secrets. Nothing is bootstrapped by hand.
- **BREAKING** Tenant AppProjects allow no cluster-scoped resources and only the tenant's own namespaces.
- **BREAKING** Platform services move to their own namespaces (`kubeflow`, `kserve`, `openmetadata`, `polaris`, `langfuse`, `llm-gateway`, `models`). Tenant namespaces are `marketplace`, `gateway`, `gateway-data`, `gateway-ml` and `gateway-llm`.
- **BREAKING** Kubeflow switches to native multi-user mode, with tenant ML namespaces as Profiles. It stays vendored.
- **BREAKING** Object storage access becomes per-workload identity. A workload exchanges its projected Kubernetes ServiceAccount token at the RustFS STS endpoint for short-lived credentials scoped by a policy for that ServiceAccount. The static RustFS users, keys and `OBJECT_*_ACCESS_KEY_ID` secrets are removed.
- **BREAKING** Doppler keeps only secrets that originate outside the cluster: third-party tokens, human logins and infrastructure credentials. Internal credentials are generated in the cluster, either by the owning operator (CNPG, Strimzi) or by ESO generators, and never written to Doppler. OpenTofu no longer copies values between Doppler projects.
- **BREAKING** The shared model gateway authenticates tenant clients by their ServiceAccount tokens instead of issued API keys.
- The platform runs one instance each of Langfuse, the model gateway, shared model serving with its cache, and Polaris.
- Prod stays retired. Only dev is rebuilt and verified.

## Non-goals

- Splitting OpenTofu into the consumer repositories.
- Replacing vendored Kubeflow, or building a central sizing table.
- Sharing one Kafka, ClickHouse or Postgres instance between tenants.
- Prod object identity on GCS. It is designed later, when prod returns.
- Rewriting application code beyond endpoints, namespaces, secret names and credential providers. S3 clients switch to the standard web-identity credential chain.

## Capabilities

### New Capabilities
- `platform-tenancy`: the tenant inventory, the namespaces, and the namespaced-only boundary.
- `shared-llm-services`: platform-run Langfuse, model gateway and model serving, and how tenants access them.
- `ml-platform-tenancy`: Kubeflow multi-user Profiles and the shared training runtimes.
- `workload-object-identity`: short-lived, per-ServiceAccount object storage credentials issued from a Kubernetes identity.

### Modified Capabilities
- `doppler-secret-delivery`: Doppler holds only externally originated secrets, and internal credentials are generated in the cluster. A Doppler store is namespaced per tenant and exists only when the tenant needs one. There is no cross-project copying.
- `ml-object-staging`: per-workload identity replaces purpose-scoped static keys and Doppler key handoff.
- `iceberg-catalog`: Polaris runs only from the platform, in its own namespace.

## Impact

- **talos-proxmox:**
  - `apps/argocd/platform`
  - `apps/components/{kubeflow,openmetadata,external-secrets,agentgateway,cloudflare-tunnel,substrate,auth,observability,kagent,agentregistry}`
  - new `tenants`, `langfuse`, `llm-gateway`, `models` and `polaris` components
  - `terraform/foundation` (RustFS identity provider and policies, Doppler pruning)
  - `terraform/modules/proxmox` (service-account issuer)
  - `terraform/platform`
  - docs: gitops, secrets reference
- **RustFS on TrueNAS:** OpenID identity provider settings.
- **Doppler:** most keys deleted from `talos-proxmox`. The `payment-gateway-fraud-detection` and `refurbished-marketplace` projects are deleted unless they keep external secrets.
- **Consumer repositories:** chart consolidation, namespaces, generated secrets and web-identity S3 clients. Each gets its own OpenSpec change.
- **Rollout:** dev, its Doppler internal keys and its RustFS users are wiped and rebuilt.
