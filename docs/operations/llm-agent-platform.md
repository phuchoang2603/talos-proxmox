# LLM and agent platform

The platform pins KServe presets to v0.21.0, agentgateway to v1.7.0, kagent to 0.10.4, agentregistry to 0.4.0, and Agent Substrate to 0.0.9. Talos remains 1.13.9 and Kubernetes remains 1.36.3. KEDA and Kueue are not installed.

KServe's upstream `kserve-runtime-configs` chart contains the `kserve-config-llm-*` presets; `kserve-llmisvc-resources` contains controller resources. The Kubeflow component installs only the presets in `ml`, without another controller, serving runtimes, or GIE CRDs. Each agentgateway, kagent, and Substrate component includes its own pinned CRD chart. agentgateway starts after the existing inference CRDs and supplies GatewayClass `agentgateway`; application charts own Gateways, routes, and policies.

| Consumer contract | Name |
| --- | --- |
| GatewayClass | `agentgateway` |
| Preset namespace | `ml` |
| Registry HTTP API | `http://agentregistry.agentregistry.svc:12121` |
| kagent namespace / UI | `kagent` / `kagent-ui:8080`, ClusterIP |
| WorkerPool | `kagent/kagent-default`, one gVisor worker |
| Worker mesh principal | `cluster.local/ns/kagent/sa/default` |
| Substrate API | `dns:///api.ate-system.svc:443` |
| Substrate snapshots | `s3://platform-dev/substrate/` in dev; `s3://platform-prod-142737101504-us-east-1/substrate/` in prod |

The kagent chart creates its WorkerPool and worker pods in its own namespace. Both `kagent` and `ate-system` allow privileged pods; `kagent` joins Istio ambient so actor traffic carries the worker identity. The app's mesh policy must admit that principal to its gateway. No gateway, model, default ModelConfig, built-in agent, or built-in tool is installed by this platform set. kagent watches `ml` and `kagent`; agentregistry's namespaced RBAC is restricted to `ml`.

kagent and agentregistry each use a single CNPG PostgreSQL instance and a 2 GiB PVC. Substrate uses JWT authentication and the upstream six-member Valkey cluster. Its RustFS deployment is disabled. Prod PostgreSQL instances and Valkey pods select On-Demand capacity. The Substrate 0.0.9 chart is vendored under `apps/components/substrate/vendor/substrate` to expose `valkey.nodeSelector` for its StatefulSet and initialization Job. The snapshot identity can access only `substrate/` in the environment's existing platform bucket. Application SandboxAgents must set their snapshot location under that prefix; the upstream default is a GCS location.

The UIs use Cloudflare Tunnel and the existing Istio ingress with the shared OAuth2 Proxy in `auth` (7.15.5, chart 10.7.1). Dex login is restricted to the configured platform operator email. The underlying UI Services remain ClusterIP, and in-cluster registry clients continue using the registry Service directly. Browser sessions use the shared Kubeflow OIDC client with a callback on each UI host. Secure cookies are scoped to the matching UI hostname, with separate names for dev and prod. The ingress always checks UI requests through the shared proxy, including requests with an Authorization header; the existing Kubeflow JWT policy continues protecting its routes.

| UI | Dev | Prod |
| --- | --- | --- |
| kagent | `https://kagent-dev.phuchoang.sbs` | `https://kagent.phuchoang.sbs` |
| Agent Registry | `https://agentregistry-dev.phuchoang.sbs` | `https://agentregistry.phuchoang.sbs` |

## Credentials

All private credentials live in platform Doppler `dev` / `prod` and reach pods through External Secrets. The public Substrate CA is stored in tracked Helm values (`caBundle`), which Argo CD renders into the upstream `ateapi-ca` ConfigMap. Standalone `.crt` files remain ignored. The TLS server certificate expires after one year; rotate the full credential set and update the matching public CA before expiry.

The CNPG passwords are `KAGENT_POSTGRES_PASSWORD` and `AGENTREGISTRY_POSTGRES_PASSWORD`. JWT-mode TLS and signing material uses `SUBSTRATE_CA_CERT`, `SUBSTRATE_SERVER_CERT`, `SUBSTRATE_SERVER_KEY`, `SUBSTRATE_SESSION_JWT_POOL`, and `SUBSTRATE_SESSION_CA_POOL`. Provision these in Doppler and set the matching public API CA in Helm values before installing Substrate.

Foundation manages the prod snapshot IAM identity. For dev, attach `terraform/cluster/env/dev/minio-substrate-policy.json` to a dedicated MinIO identity and save its credentials as `OBJECT_SUBSTRATE_ACCESS_KEY_ID` and `OBJECT_SUBSTRATE_SECRET_ACCESS_KEY` in platform Doppler.
Talos issues new service-account tokens with `https://kubernetes.default.svc.cluster.local` and continues accepting the cluster's API endpoint as a second issuer, preserving existing tokens. Substrate's `auth.jwt.issuer` matches the service DNS issuer so its JWT discovery uses the Kubernetes CA and authenticated discovery requests. Applying this configuration restarts the API server; newly created Substrate and kagent pods obtain tokens with the new issuer. No PodCertificate or ClusterTrustBundle feature gates are enabled.

## Rollout

PR provisioning applies dev. Prod remains manual through **Manual Provision** on main after explicit rollout confirmation. Restricting prod's shared training GPU pool to `g6.xlarge` also restricts Kubeflow training. Installing these controllers does not create an application Gateway or launch a GPU node.
