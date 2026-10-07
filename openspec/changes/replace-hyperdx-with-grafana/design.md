## Context

See proposal.md for motivation. The current state that shapes the approach:

- `apps/components/observability/` (prod, `observability` namespace, wave `1`) wraps ClickStack 3.4.0 for HyperDX only and `opentelemetry-collector` as `otel-gateway`. It templates the `ClickHouseCluster`/`KeeperCluster` named `clickstack`, a `MongoDBCommunity` named `hyperdx-mongodb` with MCK database RBAC, four ExternalSecrets, and the `hyperdx-ui` LoadBalancer Service at `10.69.12.128:80`.
- ClickHouse users are defined in `extraUsersConfig`, which the operator writes verbatim to `users.d/`. The `app` user (`SHOW ON *.*, SELECT ON system.*, SELECT ON default.*`) exists for the UI. Its password is `CLICKHOUSE_APP_PASSWORD` in the `clickhouse-credentials` Secret.
- Measured on prod: HyperDX uses 41m CPU and 366Mi, MongoDB with its agent uses 158m and 140Mi, and the MCK operator uses 53Mi. ClickHouse uses 1.1 of its 2 GiB limit. prod-server2, where HyperDX and MongoDB run, is at 73% memory.
- Platform Applications use `ServerSideApply=true`, so large ConfigMaps are not limited by the client-side `last-applied-configuration` annotation.
- The MCK operator runs in `operators` on both clusters. `hyperdx-mongodb` is its only `MongoDBCommunity` in this repository.
- The Grafana chart moved to `grafana-community/helm-charts`. Its current release is 13.2.7 (Grafana 13.2.3). ClickHouse plugin 4.22.1 requires Grafana 11.6 or later. Its linux-amd64 package is 14 MB, larger than a ConfigMap can hold.
- The plugin repository's `src/dashboards/` at tag `v4.22.1` holds eight bundled dashboards, about 405 KB in total. Their panels select the data source through a dashboard variable, and their `__inputs` declare `DS_GRAFANA_CLICKHOUSE_DATASOURCE` or `the_datasource` for UI import.

## Goals / Non-Goals

**Goals:**
- Every piece of Grafana configuration that matters comes from Git or Doppler, so a pod restart or prod rebuild reproduces the same UI.
- No change to ingest, the table schema, or retention.
- Stay on the upstream chart so upgrades are version bumps.

**Non-Goals:**
- Dex or other single sign-on. That is a separate change, `publish-dex-sso-via-cloudflare`.
- Alert rules and contact points.
- Custom node, pod, or Kubernetes event dashboards over `otel_metrics_*`. Events remain searchable in the logs explorer.
- Changing metric temporality (for example a `cumulativetodelta` processor in the gateway).
- Removing the MongoDB operator.
- Migrating saved HyperDX searches.

## Decisions

### Grafana as a subchart of `observability`

```
 observability (prod)                         before → after
 ┌───────────────────────────────────────────────────────────────┐
 │ clickstack subchart (HyperDX)        ──▶  grafana subchart     │
 │ templates/mongodb.yaml               ──▶  (removed)            │
 │ files/sources.json                   ──▶  dashboards/*.json    │
 │ ExternalSecrets: hyperdx, mongodb pw ──▶  grafana-admin        │
 │ hyperdx-ui LB 10.69.12.128           ──▶  grafana-ui LB, same  │
 │ clickhouse.yaml, otel-gateway, clickhouse-credentials: kept   │
 └───────────────────────────────────────────────────────────────┘
```

Grafana replaces ClickStack as a dependency of the existing chart, pinned to chart 13.2.7, with its archive committed like the others. The wrapper keeps owning the UI LoadBalancer Service, renamed `grafana-ui`, at `10.69.12.128:80`, selecting the Grafana pods and targeting port 3000. The chart's own ClusterIP Service stays internal, as `istio-ambient-ingress` requires.

Alternative considered: a separate `grafana` component. The data source needs the ClickHouse Service name and the `clickhouse-credentials` Secret from this chart. Splitting would add a cross-Application dependency for one Deployment.

### Stateless Grafana

`persistence.enabled: false`, so the SQLite database lives in the pod's `emptyDir`. The data source, dashboard provider, dashboards, and admin account are provisioned at startup. A restart loses sessions and UI-made edits, which is documented. Dashboards are changed by editing Git.

Grafana runs one replica with requests of 100m CPU and 256Mi memory and a 512Mi memory limit, unpinned. With no PVC, it may also run on AWS burst workers.

Alternatives considered: SQLite on a local-path PVC, which pins Grafana to one node and keeps UI edits outside Git; and CNPG PostgreSQL, which adds about 200Mi and a database for state the operator does not want kept.

### Plugin downloaded at startup

The chart's `plugins` value installs `grafana-clickhouse-datasource` pinned to 4.22.1 into the `emptyDir` plugin directory on every start. That needs outbound HTTPS to grafana.com.

Alternatives considered: a custom image built in CI, which is the repository's first image pipeline and registry; and a committed zip fetched by an init container, which adds 14 MB to Git per upgrade and still downloads at startup.

### Dashboards copied into Git

All eight files from `src/dashboards/` at plugin tag `v4.22.1` go into `apps/components/observability/dashboards/`: `otel-logs-explorer.json`, `otel-logs-explorer-json.json`, `otel-traces-explorer.json`, `otel-service-dashboard.json`, `system-dashboards.json`, `query-analysis.json`, `data-analysis.json`, and `cluster-analysis.json`. Two of them show little today. `cluster-analysis.json` reports replication, and the store has one replica. `otel-logs-explorer-json.json` targets JSON-typed log tables, which the exporter does not create. Both are kept so they work if the store or schema changes.

When copying, the import placeholders `${DS_GRAFANA_CLICKHOUSE_DATASOURCE}` and `${the_datasource}` are replaced with the provisioned data source UID `clickhouse`. File provisioning does not resolve `__inputs`, so without this the dashboard variable would depend on Grafana's fallback behavior. `system-dashboards.json` ships without a `uid`, so it gets `clickhouse-system`. Otherwise a stateless Grafana would generate a new UID, and a new URL, on every start. The plugin tag is recorded in a comment in `values.yaml`. An upgrade copies the files again and repeats the substitution.

The wrapper renders one ConfigMap, `grafana-dashboards`, from `.Files.Glob "dashboards/*.json"`. It is about 405 KB, under the 1 MiB limit. A file provider loads it into a `ClickHouse` folder with `allowUiUpdates: false`. The chart's dashboard sidecar stays disabled.

### Data source

A provisioned `grafana-clickhouse-datasource`:

- UID `clickhouse`, default data source, `editable: false`.
- Native protocol to `clickstack-clickhouse-headless.observability.svc:9000`, user `app`, password `$__env{CLICKHOUSE_APP_PASSWORD}` in `secureJsonData`. The variable comes from `clickhouse-credentials` through the chart's `envValueFrom`.
- `logs`: database `default`, table `otel_logs`, `otelEnabled: true`.
- `traces`: database `default`, table `otel_traces`, `otelEnabled: true`, with trace and log links shown.

The plugin's OTel mode uses the column names that the gateway's `clickhouse` exporter creates, so no column mapping is needed.

### Bounded UI queries

`extraUsersConfig` gains a `profiles.grafana` entry with `max_memory_usage` of 512 MiB and `max_execution_time` of 60 seconds. The `app` user switches from profile `default` to `grafana`. Its grants stay read-only, adding only `READ ON REMOTE`, because the Advanced ClickHouse Monitoring dashboard reads `clusterAllReplicas(default, ...)`. The `default` cluster has an interserver secret, so those reads run as `app`, with its grants and profile. `WRITE ON REMOTE` is not granted. `readonly` is not set, because the plugin sends query settings. With these limits a heavy dashboard fails its own query instead of pushing ClickHouse toward its 2 GiB limit.

### Login

`admin.existingSecret` points at an ESO Secret `grafana-admin` with user `admin` and password `GRAFANA_ADMIN_PASSWORD`. `grafana.ini` sets `users.allow_sign_up = false`, leaves anonymous access off, and turns off update checks and usage reporting. `server.root_url` is `http://10.69.12.128`. Grafana's built-in failed-login lockout stays on.

### Credentials

`terraform/foundation` removes `HYPERDX_MONGODB_PASSWORD` and the `random_uuid` `HYPERDX_API_KEY`, and adds `GRAFANA_ADMIN_PASSWORD` to the prod-only `random_password.observability` set. Applying it deletes the two retired keys from Doppler, as the "unused keys" rule in `doppler-secret-delivery` requires.

## Risks / Trade-offs

- [grafana.com unreachable when the pod starts] → The plugin fails to install and the data source does not work until a restart succeeds. Accepted by the operator. A custom image is the fallback if this recurs.
- [Every new pod migrates an empty database, which took about 2.5 minutes on prod-server1 versus 16 seconds on a workstation] → A startup probe allows up to 10 minutes before liveness checks begin. An in-memory `emptyDir` would be faster, but would count about 90 MB of database and plugins against Grafana's memory limit.
- [Dashboards edited in the UI are lost on restart] → Provision them with `allowUiUpdates: false`, so Grafana shows them as provisioned. Document that changes go through Git.
- [Copied dashboards drift from the plugin version] → Record the plugin tag next to the plugin version and update both together.
- [Placeholder substitution misses a reference] → Verify after rollout that every panel in all eight dashboards loads data or returns an empty result without a data source error.
- [No node or pod resource dashboards] → Accepted. The metric tables stay queryable in Explore, and dashboards can come in a later change.
- [The admin password is the only login] → It is random, held only in Doppler, and protected by Grafana's lockout. The address is LAN-only.
- [HyperDX MongoDB volumes stay on their node] → MCK's StatefulSet keeps its claims. Delete them after the cutover is verified.
- [The query limits are too tight for some prebuilt panels] → Raise the profile values in Git. They are store protection, not a quota.

## Migration Plan

1. Operator applies `terraform/foundation` locally. It confirms that `GRAFANA_ADMIN_PASSWORD` exists in prod and the two HyperDX keys are gone. The running HyperDX keeps its existing Secrets meanwhile, because ESO retains them when a remote key disappears.
2. Merge. Prod's Argo CD prunes HyperDX, `hyperdx-mongodb`, and its RBAC, deploys Grafana, and moves the `.128` Service to the Grafana pods. The ClickHouse pod restarts to load the new user profile.
3. Validate Grafana at `http://10.69.12.128`. Then delete the orphaned `hyperdx-mongodb` PVCs in `observability`.

Rollback: revert the merge and the foundation change, then apply foundation again. HyperDX returns with an empty MongoDB, and its first-user signup runs again. Telemetry data is unaffected in either direction.
