## Context

See proposal.md for motivation. The current state and constraints that shape the approach:

- After `remove-longhorn-and-victoria`, neither environment has an `observability` component, a `monitoring` namespace, Victoria CRDs, or Grafana. `apps/components/observability/` does not exist.
- After that change, prod consists of three control-plane nodes that also run workloads: `prod-server1` (pve, SSD, 6 cores, 22 GB, GPU) and `prod-server2` (pve2, HDD, 6 cores, 16 GB) and `prod-server3` (pve3, HDD, 4 cores, 16 GB), each with a 364 GB disk shared by etcd and local-path volumes. Kubelet reservations protect system services. Dev is one 12 GB control-plane node with a GPU.
- The platform already runs the MongoDB Controllers for Kubernetes operator 1.12 (`mongodb-operator`, `operators` namespace, both clusters), watching `MongoDBCommunity` in all namespaces.
- ClickStack chart 3.4.0 no longer templates ClickHouse or MongoDB directly. It renders `ClickHouseCluster`/`KeeperCluster` (`clickhouse.com/v1alpha1`, official ClickHouse operator) and `MongoDBCommunity` custom resources, and puts every credential in `hyperdx.secrets` values, which are rendered into the `clickstack-secret` Secret, the ClickHouse user config, the MongoDB URI, and HyperDX's connection JSON. Setting `hyperdx.secrets: null` is supported only when the chart's ClickHouse, MongoDB, and collector are all disabled.
- The official ClickHouse operator chart (`oci://ghcr.io/clickhouse/clickhouse-operator-helm`, 0.0.8) requires cert-manager unless webhooks are disabled, as the `clickstack-operators` chart does. `ClickHouseCluster` requires `keeperClusterRef`, supports `settings.defaultUserPassword` from a Secret, container `env`/`envFrom`, and `settings.systemLogsTTLDays`.
- Prod's LoadBalancer pool is `10.69.12.128-254`. Argo CD uses `.254`, and `.128` is freed by the Longhorn change. Dev (`10.69.11.0/16`) and prod (`10.69.12.0/16`) share one L2 network, and Cilium L2 announcements answer ARP for LoadBalancer IPs.
- The foundation root is applied locally by an operator, has a workspace-level Doppler token, and already writes `ESO_DOPPLER_TOKEN` to both configs. The cluster root writes only per-environment generated credentials.
- AWS burst workers carry the `burst.talos.dev/stateless=true:NoSchedule` taint. `burst-policy` rejects only PVC-backed pods there.

## Goals / Non-Goals

**Goals:**
- One ClickHouse store on prod, fed by both environments through standard OTLP, on the standard OpenTelemetry ClickHouse exporter schema so other ClickHouse clients can query it later.
- No credential in Git, keeping the existing Doppler and ESO model.
- Stay close to upstream charts, so upgrades are version bumps.

**Non-Goals:**
- Backups of ClickHouse or MongoDB, replication, or a second ClickHouse replica.
- Fraud-detection or other analytics databases. A later change can add another `ClickHouseCluster` under the same operator.
- Alerting rules, dashboards, and HyperDX user provisioning. HyperDX's first-user signup is used.
- ServiceMonitor/PodMonitor discovery and the OpenTelemetry Operator's target allocator.
- Moving existing applications' OTLP configuration; this repo has none. Workloads in other repos point at the new endpoint.

## Decisions

### Layout: three components

```
 prod                                                  dev
 ┌─────────────────────────────────────────────┐       ┌──────────────────────────┐
 │ operators ns                                │       │ observability ns         │
 │   clickhouse-operator (new, prod)           │       │   otel-agent (DaemonSet) │
 │   mongodb-operator    (existing)            │       │   otel-cluster (1 pod)   │
 │                                             │       │        │ OTLP + token     │
 │ observability ns                            │       └────────┼─────────────────┘
 │   otel-agent DaemonSet ─┐                   │                │
 │   otel-cluster ─────────┤ OTLP              │                │
 │                         ▼                   │                │
 │   otel-gateway ◀── LB 10.69.12.129:4317/4318 ◀───────────────┘
 │        │ clickhouse exporter (TTL 168h)     │
 │        ▼                                    │
 │   ClickHouseCluster (1) + KeeperCluster (1) │  pinned to prod-server1, local-path
 │        ▲                                    │
 │   HyperDX ── MongoDBCommunity (1)           │
 │     ▲                                       │
 │   Gateway 10.69.12.128:80                   │
 └─────────────────────────────────────────────┘
```

| Component | Clusters | Namespace | Contents |
|---|---|---|---|
| `clickhouse-operator` | prod | `operators` | official operator chart, webhooks and cert-manager off, CRDs on |
| `observability` | prod | `observability` | ClickStack chart (HyperDX only), OpenTelemetry Collector chart as gateway, ClickHouse/Keeper/MongoDB custom resources, ExternalSecrets, Gateway |
| `otel-agent` | dev, prod | `observability` | OpenTelemetry Collector chart twice: a DaemonSet agent and a single-replica cluster collector |

Sync waves: `clickhouse-operator` at `0` with the other operators, `observability` at `1`, `otel-agent` at `2`. The agent can start before the gateway is ready; its exporters retry. On prod both components share the `observability` namespace, and both declare the same privileged namespace metadata: the agent needs it for hostPath volumes, and the store's pods then never depend on which Application labels the namespace first.

Alternative considered: one component holding everything. Dev would need values that disable all store resources, and the two environments would diverge inside one chart.

### ClickHouse operator: official, without cert-manager

The ClickStack chart's custom resources target the official operator, so that is what runs. It is installed directly, not through `clickstack-operators`, because that chart also installs a second MongoDB operator (MCK 1.7) that would collide with the existing 1.12 install and its CRDs. Values mirror `clickstack-operators`: `webhook.enabled: false`, `certManager.enabled: false`, `crd.enabled: true`. The chart is committed as a pinned archive like other components.

Alternative considered: Altinity's operator. It is more mature, but the ClickStack chart's ClickHouse handling would have to be rewritten against another CRD. Because the chart's ClickHouse templates are bypassed anyway (next decision), this remains a cheap switch if the `v1alpha1` API proves unstable. Observability data is disposable, so the risk is acceptable now.

### ClickStack chart for HyperDX only; custom resources owned by the wrapper

The chart puts credentials in values, which the secrets spec forbids. The wrapper therefore disables `clickhouse`, `mongodb`, and `otel-collector` in the chart, blanks every `hyperdx.secrets` key, and owns those pieces itself. The chart's `hyperdx.secrets: null` option is not used: Argo CD's Helm 3.19 honors it, but Helm 4 keeps a subchart's map defaults when the parent sets null, which would render the chart's placeholder passwords. Blank keys render an empty `clickstack-secret` in both, and HyperDX's explicit `env` entries take precedence over its `envFrom`.

- **`KeeperCluster`**: 1 replica, 5 Gi local-path claim, image pinned to `clickhouse/clickhouse-keeper:25.7-alpine` (the operator defaults to `latest`).
- **Volume permissions**: the operator mounts both data volumes through `subPath`s. On local-path hostPath volumes the kubelet creates those directories as root and ignores `fsGroup`, so ClickHouse and Keeper (uid 101) cannot start. Both pods get a root init container, using the pod's own image with only `CHOWN`, that creates the two directories and chowns them to 101.
- **`ClickHouseCluster`**: 1 shard, 1 replica, `keeperClusterRef` to the Keeper. The image tag matches the chart default (`25.7-alpine`), with a 2 Gi memory request and limit. Settings are copied from the chart's defaults: `logger` at `information`, 100M × 10 files, and `systemLogsTTLDays: 7`. Two additions: `storage_configuration` sets `keep_free_space_bytes` on the default disk (20 GiB), because local-path does not enforce the claim size, and `defaultUserPassword` comes from the ESO Secret.
- **ClickHouse users**: `otelcollector` (`SELECT, INSERT, CREATE, SHOW ON default.*`) and `app` (`SHOW ON *.*, SELECT ON system.*, SELECT ON default.*`), matching the chart. They are defined in `extraUsersConfig`, with passwords read from container environment variables sourced from the ESO Secret through ClickHouse's `from_env` substitution.
- **`MongoDBCommunity`**: 1 member, SCRAM user `hyperdx` whose `passwordSecretRef` points at the ESO Secret. The spec is otherwise copied from the chart's, on local-path with default claim sizes. MCK runs database pods as ServiceAccount `mongodb-kubernetes-appdb` but, when watching all namespaces, creates it only in its own namespace, so the wrapper adds that ServiceAccount, Role, and RoleBinding (copied from MCK's `database-roles.yaml`) in `observability`.
- **HyperDX**: `useExistingConfigSecret: true`, pointing at an ESO-templated Secret with `connections.json` (ClickHouse HTTP endpoint, user `app`) and `sources.json` (the chart's default logs, traces, metrics, and sessions sources). `MONGO_URI` and `HYPERDX_API_KEY` come from `deployment.env` `valueFrom` the ESO Secret. `FRONTEND_URL` is `http://10.69.12.128`.

Alternatives considered:
- Use the chart as-is and relax the secrets spec for in-cluster database passwords. This is simpler, but the repository is public, and the passwords would be in Git.
- Drop the ClickStack chart and template the HyperDX Deployment too. That gives more control, but duplicates a maintained Deployment for no benefit.

### Gateway collector: upstream OpenTelemetry Collector, not ClickStack's

The gateway is the `opentelemetry-collector` chart in `deployment` mode with the contrib image. It uses:

- OTLP gRPC and HTTP receivers behind the `bearertokenauth` extension, with the token from the ESO Secret.
- `memory_limiter` and `batch` processors.
- The `clickhouse` exporter against `tcp://<cluster>:9000`, database `default`, user `otelcollector`, with `create_schema: true` and `ttl: 168h`.

That exporter produces the standard `otel_logs`, `otel_traces`, and `otel_metrics_*` tables that HyperDX's default sources read. The gateway Service is `LoadBalancer` with `lbipam.cilium.io/ips: 10.69.12.129`. Prod's agents use the same Service's cluster IP through `otel-gateway.observability.svc`, so no second Service is needed.

Alternative considered: ClickStack's collector image with OpAMP management by HyperDX. It ties collector configuration and ingest auth to HyperDX's runtime state instead of Git, and the chart's collector is disabled anyway because of the secrets constraint.

### Agents: DaemonSet plus cluster collector in each environment

`otel-agent` wraps the `opentelemetry-collector` chart twice.

**Agent** (DaemonSet), with the chart presets `logsCollection` (with checkpoints), `kubeletMetrics`, `hostMetrics`, and `kubernetesAttributes`:
- Adds an OTLP receiver. Its Service uses `internalTrafficPolicy: Local`, so applications everywhere send to `otel-agent.observability.svc:4317`/`4318` and reach their node's agent.
- Tolerates all taints, so it also runs on AWS burst workers.
- Checkpoints and the export queue use `file_storage` on a hostPath under `/var/lib/otelcol`, not a PVC.

**Cluster collector** (Deployment, 1 replica):
- Uses the presets `clusterMetrics` and `kubernetesEvents`.
- Adds a `prometheus` receiver scraping pods annotated `prometheus.io/scrape: "true"`.

**Both:**
- Add `k8s.cluster.name` (`dev-talos`/`prod-talos`) and `deployment.environment` (`dev`/`prod`) through a `resource` processor with `upsert`, so applications cannot mislabel their environment.
- Export OTLP gRPC to the gateway: prod through the in-cluster Service, dev to `10.69.12.129:4317`.
- Send the ingest token from the ESO Secret as an `authorization: Bearer` header on the OTLP exporter. The `bearertokenauth` client extension is not used because it refuses to send credentials over plaintext gRPC; the gateway still validates the header with `bearertokenauth`. The token is used even in-cluster so the gateway has a single auth path.
- Bound retries and the sending queue (for example 15 minutes of retry and a fixed queue size), so a prod outage drops data instead of growing without limit.

Per-environment differences are only the export endpoint and resource attribute values, in `environments/<env>/values.yaml`.

Alternative considered: dev ships straight to ClickHouse. It would put ClickHouse credentials in dev and expose the native port on the LAN.

### Credentials generated by the foundation root

`terraform/foundation` adds the `hashicorp/random` provider and writes:

| Doppler key | Configs | Consumer |
|---|---|---|
| `OTEL_INGEST_TOKEN` | dev, prod | gateway `bearertokenauth`, agents' exporters |
| `CLICKHOUSE_DEFAULT_PASSWORD` | prod | `defaultUserPassword` |
| `CLICKHOUSE_OTEL_PASSWORD` | prod | `otelcollector` user, gateway exporter |
| `CLICKHOUSE_APP_PASSWORD` | prod | `app` user, HyperDX `connections.json` |
| `HYPERDX_MONGODB_PASSWORD` | prod | MongoDB user, `MONGO_URI` |
| `HYPERDX_API_KEY` | prod | HyperDX (`random_uuid`) |

The foundation root is used because only it writes to both configs, which is required for the shared ingest token. Keeping all telemetry credentials there also means they survive environment destroys, which only touch cluster and platform state. Each component has one ExternalSecret per consuming namespace, following the tunnel's pattern. The ESO `template` feature assembles `MONGO_URI` and `connections.json` from the individual keys.

Alternative considered: the cluster root generates prod's credentials. It cannot write the ingest token into dev's config, because environments must not write to each other's configs.

### Placement and sizing

`ClickHouseCluster` and `KeeperCluster` use `nodeSelector: kubernetes.io/hostname: prod-server1`, so local-path provisions both volumes on the only SSD-backed node. Keeping ClickHouse's merge writes off `prod-server2` and `prod-server3` protects etcd on their HDDs.

`prod-server1` also runs an etcd member on the same SSD. ClickHouse therefore caps background merge concurrency (`background_pool_size` of 4 instead of the default 16) so merges cannot saturate the disk. Expected use is about 2.5 Gi of memory requests for ClickHouse and Keeper, well within the node's 22 GB.

MongoDB, HyperDX, the gateway, and the cluster collector are not pinned. MongoDB's write rate is small enough for any node.

## Risks / Trade-offs

- [Official operator is `v1alpha1` / chart 0.0.8] → Pin the chart. The custom resources live in the wrapper, so a move to Altinity touches only the wrapper's templates.
- [`from_env` passwords in `extraUsersConfig` may not render as expected through the operator] → The operator writes `extraUsersConfig` verbatim as JSON into `users.d/99-extra-users-config.yaml`; a local test of that file against `clickhouse-server:25.7-alpine` authenticated both users from environment variables. Confirm on prod after rollout. Fallback: a PostSync Job that creates the two users with SQL through the `default` user, whose password is supported natively from a Secret.
- [Upstream exporter schema drifts from what HyperDX's default sources expect] → Pin the collector version, and verify that HyperDX's logs, traces, and metrics views load against the created tables before rollout.
- [Single node, no backups] → Accepted. A `prod-server1` outage stops ingest for both environments. Agents buffer only briefly.
- [ClickHouse merges raise etcd fsync latency on `prod-server1`] → Cap merge concurrency. After rollout, check etcd's `wal_fsync` and `backend_commit` latency metrics in HyperDX. If they degrade, lower the cap further or move ClickHouse to a dedicated disk in a later change.
- [local-path ignores claim sizes] → Use a 7-day TTL, bound the system logs, and set `keep_free_space_bytes`, so ClickHouse refuses inserts before the node's disk fills.
- [Loss of alerting] → Accepted until HyperDX alerts are configured in a later change.
- [HyperDX first-user signup on an internal address] → Anyone on the LAN who reaches the UI first can create the first account. Create the operator account immediately after rollout.
- [Agent DaemonSet on AWS workers adds per-node overhead that Karpenter must size for] → Keep agent requests small (for example 50m CPU, 128Mi).

## Migration Plan

1. Merge and archive `remove-longhorn-and-victoria` first. This change's deltas are written against its spec text.
2. Operator applies `terraform/foundation` locally and confirms the six keys exist in the right Doppler configs.
3. Merge. Prod's Argo CD syncs `clickhouse-operator`, then `observability`, then `otel-agent`. Dev's Argo CD syncs `otel-agent`.
4. Validate in HyperDX: dev and prod logs, node metrics, events, and a test trace, filtered by `deployment.environment`.

Rollback: revert the merge and recreate the clusters from empty state. That leaves both environments without observability, as after `remove-longhorn-and-victoria`. The foundation credentials can stay.
