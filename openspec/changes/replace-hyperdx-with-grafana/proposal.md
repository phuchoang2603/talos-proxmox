## Why

HyperDX, the UI from `add-clickstack-observability`, needs its own MongoDB, keeps its configuration in that database rather than Git, and gives the LAN's first visitor the admin account. The operator prefers Grafana with the ClickHouse data source plugin over the same ClickHouse store. The plugin ships OpenTelemetry log, trace, and service dashboards plus ClickHouse health dashboards, and works with Grafana alerting later.

## What Changes

- **BREAKING:** Remove HyperDX from prod: the ClickStack chart dependency, the HyperDX `MongoDBCommunity` instance and its database RBAC, the HyperDX source definitions, and the HyperDX ExternalSecrets. Saved HyperDX searches and its account are lost.
- Add Grafana to the prod `observability` component. It is stateless: the ClickHouse data source, dashboards, and admin account come from Git and Doppler, and a restart loses only sessions and UI-made edits.
- Install the ClickHouse data source plugin at a pinned version, downloaded from grafana.com when the pod starts.
- Copy all of the plugin's bundled dashboards into the repository and provision them from files: the OpenTelemetry logs (both table variants), traces, and service dashboards, and the ClickHouse system, query, data, and cluster analysis dashboards.
- Read ClickHouse through the existing read-only `app` user, and add per-query memory and time limits for that user so dashboards cannot exhaust the store.
- Serve Grafana on the same internal address, `10.69.12.128`, port 80. Log in with an admin password generated into Doppler. Self sign-up is disabled.
- Generate `GRAFANA_ADMIN_PASSWORD` in the foundation root, and delete `HYPERDX_MONGODB_PASSWORD` and `HYPERDX_API_KEY`.
- Keep the MongoDB operator installed in both environments, although no component in this repository uses it after this change.
- Leave ingest unchanged: the agents, the OTLP gateway, the ClickHouse server, Keeper, the tables, and the 7-day retention.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cluster-observability`: Grafana replaces HyperDX as the only telemetry UI. The UI is stateless and provisioned from Git, its store queries are bounded, and its credentials change.
- `istio-ambient-ingress`: prod's UI LoadBalancer Service serves Grafana instead of HyperDX.
- `declarative-platform-bootstrap`: Argo CD owns the Grafana UI LoadBalancer Service instead of HyperDX's.
- `doppler-secret-delivery`: the foundation root also generates the telemetry UI's admin credential.

## Impact

- **Charts:** `apps/components/observability/` drops the `clickstack` dependency, `templates/mongodb.yaml`, and `files/sources.json`. It adds the `grafana` chart from `grafana-community/helm-charts`, the dashboard JSON files, and dashboard ConfigMaps. It also changes the ExternalSecrets, `templates/ui-service.yaml`, `templates/clickhouse.yaml` (the `app` user's settings profile), `values.yaml`, `Chart.yaml`, `Chart.lock`, and the committed chart archives.
- **OpenTofu:** `terraform/foundation/doppler.tf` changes its generated prod keys. An operator applies it locally.
- **Argo CD:** no new Application. `observability` keeps its name, namespace, and sync wave.
- **Network:** `10.69.12.128` stays the UI address. Grafana needs outbound HTTPS to grafana.com at startup.
- **Docs:** `docs/architecture/gitops.md`, `docs/operations/cluster-access.md`, `docs/reference/secrets.md`, and `docs/operations/kubeflow.md`.
- **Operations:** the HyperDX MongoDB volumes remain on their node until deleted. Grafana cannot query ClickHouse if grafana.com is unreachable when its pod starts.
