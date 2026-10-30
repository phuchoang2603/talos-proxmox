# LLM and agent platform

The platform pins KServe presets to v0.21.0, agentgateway to v1.7.0, kagent to 1.0.0-rc1, agentregistry to 0.4.0, and Agent Substrate and its podcertificate controller to 1.0.0-rc1. Talos is 1.14.5 and Kubernetes is 1.37.2. KEDA is pinned to 2.21.0 in `operators`; Kueue is not installed.

KServe's upstream `kserve-runtime-configs` chart contains the `kserve-config-llm-*` presets; `kserve-llmisvc-resources` contains controller resources. The Kubeflow component installs only the presets in `ml`, without another controller, serving runtimes, or GIE CRDs. Each agentgateway, kagent, and Substrate component includes its own pinned CRD chart. agentgateway starts after the existing inference CRDs and supplies GatewayClass `agentgateway`; application charts own Gateways, routes, and policies.

| Consumer contract | Name |
| --- | --- |
| GatewayClass | `agentgateway` |
| Preset namespace | `ml` |
| Registry HTTP API | `http://agentregistry.agentregistry.svc:12121` |
| kagent namespace / UI | `kagent` / `kagent-ui:8080`, ClusterIP |
| WorkerPool | Application-owned in `llm-agents`, `ate.dev/v1` |
| Actor egress mesh principal | `cluster.local/ns/ate-system/sa/atenet-egress`; workers stay outside ambient |
| Substrate API | `dns:///api.ate-system.svc:443` |
| Substrate snapshots | `s3://platform-dev/substrate/llm-agents/…` in dev; `s3://platform-prod-142737101504-us-east-1/substrate/llm-agents/…` in prod |

The platform owns `llm` with Istio ambient and Pod Security enforce/audit/warn set to `restricted`, and `llm-agents` with privileged Pod Security and no ambient enrollment. Application charts own agents, Harnesses, WorkerPools and ScaledObjects in `llm-agents`. kagent watches `llm`, `llm-agents` and `kagent`; agentregistry watches `llm`. KServe presets remain in `ml`. No default WorkerPool, model, ModelConfig or built-in tool is installed.

kagent resources use `api.kagent.dev/v1alpha3`; Substrate resources use `ate.dev/v1`. WorkerPools use `ghcr.io/kagent-dev/substrate/ateworker-gvisor:v1.0.0-rc1`, the shared `gvisor-default` SandboxConfig, and both `kagent.dev/worker-pool-name` and `kagent.dev/worker-pool-namespace` discovery labels. Every runtime has positive CPU and memory limits (defaults: 1 CPU, 1 GiB). Atelet supplies node access and gVisor assets; a Kubernetes RuntimeClass is unnecessary. The WorkerPool scale subresource publishes its pod selector for KEDA.

Actors egress through Substrate's per-actor policy enforcement and credential injection. Only `atenet-egress` is enrolled in ambient by a workload-scoped admission label policy. Its credential provider can read Secrets only in `llm-agents` for that atespace. The controller is the explicit mTLS actor-ingress principal. Its private TaskStore/Memory APIs require Actor JWTs. The kagent waypoint validates Dex, gateway and actor JWTs; actors may reach only the two private runtime gRPC services, while the UI and application gateway have separate trusted identities. Workload policies require the waypoint to prevent direct Pod-IP bypass. Gateway machine JWTs are signed per request using `KAGENT_GATEWAY_SIGNING_KEY`; public verification keys are pinned in each environment's values. Runtime telemetry endpoints belong to the application's Harness.

kagent and Substrate share `ate-system/agent-runtime-postgres`, a single CNPG PostgreSQL instance with a 2 GiB PVC and separate owner/runtime logins, roles and schemas. Agentregistry keeps its separate database. Prod databases select On-Demand capacity. Substrate has no Valkey or RustFS deployment. Its snapshot identity can access only `substrate/` in the environment bucket. Application Harnesses set an `s3://` snapshot location under this prefix.

The UIs use Cloudflare Tunnel and the existing Istio ingress with the shared OAuth2 Proxy in `auth` (7.15.5, chart 10.7.1). Dex login is restricted to the configured platform operator email. The underlying UI Services remain ClusterIP, and in-cluster registry clients continue using the registry Service directly. Browser sessions use the shared Kubeflow OIDC client with a callback on each UI host. Secure cookies are scoped to the matching UI hostname, with separate names for dev and prod. The ingress always checks UI requests through the shared proxy, including requests with an Authorization header; the existing Kubeflow JWT policy continues protecting its routes.

| UI | Dev | Prod |
| --- | --- | --- |
| kagent | `https://kagent-dev.phuchoang.sbs` | `https://kagent.phuchoang.sbs` |
| Agent Registry | `https://agentregistry-dev.phuchoang.sbs` | `https://agentregistry.phuchoang.sbs` |
| Langfuse (app-owned) | `https://langfuse-dev.phuchoang.sbs` | `https://langfuse.phuchoang.sbs` |

The platform supplies Langfuse's tunnel binding and shared authentication hosts. The application owns its VirtualService in `llm`, using `ml/kubeflow-gateway`, and routes `/oauth2/` to the shared proxy.

KEDA can query VictoriaMetrics at `http://vmsingle-vmks.observability.svc.cluster.local:8428/prometheus/api/v1/query`; Prometheus scalers should set `serverAddress` to `http://vmsingle-vmks.observability.svc.cluster.local:8428/prometheus`. Application charts own their ScaledObjects and scaling policies.

## Credentials

All private credentials live in platform Doppler `dev` / `prod` and reach pods through External Secrets. Substrate pod certificates rotate through projected Kubernetes volumes and ClusterTrustBundles. Root CA pools last one year and are not automatically renewed: rotate them before expiry using overlapping trust, publish new roots before switching signers, then update the public actor JWT verification keys when rotating that signing pool.

Database keys are `AGENT_RUNTIME_POSTGRES_PASSWORD`, `KAGENT_POSTGRES_OWNER_PASSWORD`, `KAGENT_POSTGRES_READWRITE_PASSWORD`, `SUBSTRATE_POSTGRES_OWNER_PASSWORD` and `SUBSTRATE_POSTGRES_READWRITE_PASSWORD`. Certificate/signing pools are JSON Doppler entries: `SUBSTRATE_SERVICE_DNS_CA_POOL`, `SUBSTRATE_POD_IDENTITY_CA_POOL`, `SUBSTRATE_POSTGRES_CA_POOL`, `SUBSTRATE_ACTOR_ID_CA_POOL`, `SUBSTRATE_EGRESS_MITM_CA_POOL` and `SUBSTRATE_ACTOR_ID_JWT_POOL`. The app reads `KAGENT_GATEWAY_SIGNING_KEY` for short-lived gateway machine JWTs. Agentregistry still uses `AGENTREGISTRY_POSTGRES_PASSWORD`.

Foundation manages the prod snapshot IAM identity. For dev, attach `terraform/cluster/env/dev/minio-substrate-policy.json` to a dedicated MinIO identity and save its credentials as `OBJECT_SUBSTRATE_ACCESS_KEY_ID` and `OBJECT_SUBSTRATE_SECRET_ACCESS_KEY` in platform Doppler.
Talos sets `user.max_user_namespaces=1024` for gVisor's gofer and sandbox processes. With this limit set to zero, `runsc create` fails with `fork/exec /proc/self/exe: no space left on device` even when disk space is available. This sysctl can be applied without a reboot.

Talos uses the Kubernetes service DNS issuer for service-account tokens. Kubernetes 1.37 enables PodCertificateRequest, ClusterTrustBundle and ClusterTrustBundleProjection by default; the API server additionally serves `certificates.k8s.io/v1beta1` because the pinned Substrate release uses it. No alpha feature gates are enabled.

## Rollout

PR provisioning applies dev. Prod remains manual through **Manual Provision** on main after explicit rollout confirmation. Restricting prod's shared training GPU pool to `g6.xlarge` also restricts Kubeflow training. Installing these controllers does not create an application Gateway or launch a GPU node.

The pre-1.0 agent database, CRDs, workers and snapshots are not migrated. Stop old actors and controllers, remove their runtime state and old CRDs, then install the new CRDs, certificate controller, shared database, Substrate and kagent together. Upgrade Talos nodes sequentially before Kubernetes, then validate dev certificates, actor egress and metrics before promoting prod. This does not delete application datasets from MinIO/S3.
