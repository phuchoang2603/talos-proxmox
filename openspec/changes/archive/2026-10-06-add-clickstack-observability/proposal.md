## Why

`remove-longhorn-and-victoria` removes the per-environment VictoriaMetrics stack and Grafana, leaving both environments without metrics, logs, traces, or alerting. The operator wants one ClickHouse-based store with SQL over all signals in their place, which is also the foundation for later analytics work such as fraud detection.

This change depends on `remove-longhorn-and-victoria`. It assumes that prod uses local-path storage, that prod consists of `prod-server1..3` with `prod-server1` as its only SSD-backed node, that no `observability` component or `monitoring` namespace exists in either environment, and that `10.69.12.128` is free.

## What Changes

- Add a single ClickStack deployment on prod only: one ClickHouse server with a single-replica Keeper, managed by the official ClickHouse operator; the HyperDX UI with its MongoDB metadata store; and an OpenTelemetry gateway collector that writes to ClickHouse.
- Add OpenTelemetry agents to both environments. They collect container logs, node and kubelet metrics, cluster metrics, and Kubernetes events, and receive OTLP from applications. They tag every record with its cluster and environment, and send everything to prod's gateway collector. Dev sends over the internal network with a shared ingest token.
- Retain all telemetry, and ClickHouse's own system logs, for 7 days.
- Serve HyperDX only on an internal Gateway address from prod's Cilium pool. The OTLP ingest endpoint gets its own internal LoadBalancer address.
- Pin ClickHouse and Keeper to `prod-server1` (the only SSD-backed node, on `pve`) on local-path storage. No replication and no backups for now.
- Generate the store and ingest credentials in the foundation root and deliver them through Doppler and ESO; no credential appears in Git.
- Add a `clickhouse-operator` component to prod's `operators` namespace. Reuse the existing MongoDB operator.

## Capabilities

### New Capabilities

- `cluster-observability`: collection of logs, metrics, traces, and events from both environments into one prod ClickHouse store with 7-day retention, authenticated cross-environment ingest, and an internal-only UI.

### Modified Capabilities

- `declarative-platform-bootstrap`: environments stay self-contained, except that dev may hold a write-only telemetry ingest credential for prod's collector. Prod must not depend on dev, and dev must converge without prod.
- `doppler-secret-delivery`: the foundation root generates the telemetry store credentials and the shared ingest token, and writes them to Doppler. The observability components receive them through ESO.

## Impact

- **Argo CD:** `apps/argocd/platform/values.yaml` adds `clickhouse-operator` (prod, `operators`), `observability` (prod, `observability`), and `otel-agent` (dev and prod, `observability`).
- **Charts:** new `apps/components/observability/` built around the ClickStack chart (HyperDX only), the OpenTelemetry Collector chart (gateway), and templates for `ClickHouseCluster`, `KeeperCluster`, `MongoDBCommunity`, ExternalSecrets, and Gateway resources. New `apps/components/clickhouse-operator/` and `apps/components/otel-agent/`.
- **OpenTofu:** `terraform/foundation/` adds the `random` provider, generates the credentials, and writes them to the Doppler configs. An operator applies it locally before merging.
- **Network:** prod's Cilium pool supplies `10.69.12.128` for the HyperDX UI and `10.69.12.129` for OTLP ingest. Dev reaches `10.69.12.129` over the shared LAN.
- **Docs:** `docs/architecture/gitops.md`, `docs/operations/cluster-access.md`, `docs/reference/secrets.md`, and a new observability section describing how applications send OTLP and how to reach HyperDX.
- **Operations:** there is no telemetry while prod's ClickHouse node or collector is down. Dev agents buffer for a bounded time, then drop data. Alerting is not provided until HyperDX alerts are configured.
