## 1. Credentials

- [x] 1.1 In `terraform/foundation`, add the `hashicorp/random` provider, generate `OTEL_INGEST_TOKEN` once and write it to the dev and prod configs, and generate `CLICKHOUSE_DEFAULT_PASSWORD`, `CLICKHOUSE_OTEL_PASSWORD`, `CLICKHOUSE_APP_PASSWORD`, `HYPERDX_MONGODB_PASSWORD` (alphanumeric), and `HYPERDX_API_KEY` (`random_uuid`) into the prod config only; verify `tofu validate` passes and a plan shows only new `random_*` and `doppler_secret` resources with sensitive values
- [x] 1.2 Apply the foundation root locally; verify `doppler secrets --project talos-proxmox --config prod --only-names` lists all six keys and the dev config lists only `OTEL_INGEST_TOKEN`

## 2. ClickHouse operator component

- [x] 2.1 Create `apps/components/clickhouse-operator/` wrapping `clickhouse-operator-helm` 0.0.8 with a committed chart archive and values `webhook.enabled: false`, `certManager.enabled: false`, `crd.enabled: true`, small manager resources; verify `helm template` renders the CRDs and manager Deployment with no cert-manager `Certificate` or webhook configuration
- [x] 2.2 Add `clickhouse-operator` to `apps/argocd/platform/values.yaml` (`operators`, wave `0`, `clusters: [prod]`); verify `helm template` of the platform chart renders it for prod only

## 3. Observability store component (prod)

- [x] 3.1 Create `apps/components/observability/` with a `Chart.yaml` depending on ClickStack 3.4.0 and the `opentelemetry-collector` chart (alias `otel-gateway`), and commit the archives; verify `helm dependency build` and `helm template` succeed
- [x] 3.2 Add ExternalSecrets from the `doppler` ClusterSecretStore for the ClickHouse passwords, MongoDB password, API key, ingest token, and an ESO-templated HyperDX config Secret holding `connections.json` and `sources.json`, plus an assembled `MONGO_URI`; verify `helm template` renders them and no rendered manifest contains a credential value
- [x] 3.3 Template `KeeperCluster` (1 replica, 5 Gi local-path) and `ClickHouseCluster` (1 shard, 1 replica, image `clickhouse/clickhouse-server:25.7-alpine`, 2 Gi memory, `keeperClusterRef`, `logger` information/100M/10, `systemLogsTTLDays: 7`, `keep_free_space_bytes` 20 GiB, `defaultUserPassword` from the Secret, `otelcollector` and `app` users with the chart's grants and `from_env` passwords), both with `nodeSelector` `kubernetes.io/hostname: prod-server1` and `background_pool_size: 4`; verify the resources pass `kubectl apply --dry-run=server` against the operator's CRDs on prod
- [x] 3.4 Template `MongoDBCommunity` (1 member, SCRAM user `hyperdx` with `passwordSecretRef`, spec otherwise copied from the ClickStack chart); verify the dry run passes against the existing MCK CRDs
- [x] 3.5 Configure the ClickStack chart for HyperDX only: every `hyperdx.secrets` key blank, `clickhouse.enabled`, `mongodb.enabled`, and `otel-collector.enabled` false, `useExistingConfigSecret: true` with the ESO config Secret, `MONGO_URI` and `HYPERDX_API_KEY` via `deployment.env` `valueFrom`, `FRONTEND_URL: http://10.69.12.128`; verify `helm template` renders one HyperDX Deployment whose env has no literal credentials, identically under Helm 3.19 and Helm 4
- [x] 3.6 Configure `otel-gateway`: `deployment` mode, contrib image pinned, OTLP gRPC/HTTP receivers with `bearertokenauth` from the ingest-token Secret, `memory_limiter` and `batch`, `clickhouse` exporter to the cluster's native port with user `otelcollector`, `create_schema: true`, `ttl: 168h`; a `LoadBalancer` Service with `lbipam.cilium.io/ips: 10.69.12.129`, also used in-cluster by prod's agents; verify `helm template` renders the Service and the collector config references only environment variables for secrets
- [x] 3.7 Template a Cilium `Gateway` at `10.69.12.128` port 80 and an `HTTPRoute` to the HyperDX app Service, following the Argo CD UI route pattern; verify `helm template` renders them with no hostname and no Cloudflare reference
- [x] 3.8 Add `observability` to `apps/argocd/platform/values.yaml` (`observability` namespace, wave `1`, `clusters: [prod]`); verify `helm template` of the platform chart renders it for prod only

## 4. Telemetry agent component (dev and prod)

- [x] 4.1 Create `apps/components/otel-agent/` with two `opentelemetry-collector` dependencies (aliases `agent` and `cluster`) and committed archives; verify `helm dependency build` succeeds
- [x] 4.2 Configure `agent`: `daemonset` mode, presets `logsCollection` (checkpoints on), `kubeletMetrics`, `hostMetrics`, `kubernetesAttributes`, OTLP receiver with a Service using `internalTrafficPolicy: Local`, `file_storage` on hostPath `/var/lib/otelcol` for checkpoints and the export queue, tolerate all taints, small requests; verify `helm template` renders a DaemonSet with no PVC and a toleration matching `burst.talos.dev/stateless`
- [x] 4.3 Configure `cluster`: `deployment` mode, 1 replica, presets `clusterMetrics` and `kubernetesEvents`, a `prometheus` receiver for pods annotated `prometheus.io/scrape: "true"`; verify `helm template` renders its RBAC and config
- [x] 4.4 In both, add a `resource` processor upserting `k8s.cluster.name` and `deployment.environment`, an OTLP exporter sending the ingest token as an `authorization: Bearer` header from an ESO Secret sourced from `OTEL_INGEST_TOKEN`, and bounded retry and queue; put the endpoint and attribute values in `environments/dev/values.yaml` (`10.69.12.129:4317`, `dev-talos`, `dev`) and `environments/prod/values.yaml` (`otel-gateway.observability.svc:4317`, `prod-talos`, `prod`); verify `helm template` per environment renders the expected endpoint and attributes
- [x] 4.5 Verify that `burst-policy` admits the agent DaemonSet: `kubectl apply --dry-run=server` of the rendered DaemonSet succeeds on dev
- [x] 4.6 Add `otel-agent` to `apps/argocd/platform/values.yaml` (`observability`, wave `2`, `clusters: [dev, prod]`, per-cluster value files, privileged namespace metadata for hostPath); verify `helm template` renders it for both clusters with the right value files

## 5. Documentation

- [x] 5.1 Add `clickhouse-operator`, prod-only `observability`, and `otel-agent` to the component and sync-wave tables in `docs/architecture/gitops.md`; verify the tables match `apps/argocd/platform/values.yaml`
- [x] 5.2 Update `docs/reference/secrets.md` with the six generated keys, their writer (foundation) and consumers, and the new ExternalSecret-delivered Secrets; verify the tables match design.md
- [x] 5.3 Add HyperDX `http://10.69.12.128` and the OTLP endpoints (in-cluster `otel-agent.observability.svc:4317/4318`, cross-environment `10.69.12.129`) to `docs/operations/cluster-access.md`, with the first-user signup step; verify the addresses match the chart values

## 6. Validation

- [x] 6.1 Run the lint workflow's chart and OpenTofu checks locally; verify they pass
- [x] 6.2 Verify the `from_env` user passwords on prod: `clickhouse-client --user otelcollector` and `--user app` authenticate with the Doppler values; if not, replace them with the PostSync SQL Job fallback from design.md and re-verify
- [x] 6.3 After merge, verify on prod that the `ClickHouseCluster`, `KeeperCluster`, and `MongoDBCommunity` are ready, the ClickHouse and Keeper pods run on `prod-server1`, and `otel_logs`, `otel_traces`, and `otel_metrics_*` tables exist with a 7-day TTL
- [x] 6.4 Verify an OTLP request to `10.69.12.129:4317` without the token is rejected, and that a test trace sent from a dev pod to `otel-agent.observability.svc:4317` appears in HyperDX with `deployment.environment=dev`
- [ ] 6.5 Verify HyperDX at `http://10.69.12.128` shows container logs, node metrics, and Kubernetes events from both environments, including a pod on an AWS burst worker if one is running, and navigates from a trace to its logs; create the operator account