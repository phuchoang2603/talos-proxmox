## MODIFIED Requirements

### Requirement: Single telemetry store on prod
The platform SHALL run exactly one telemetry store, on prod, backed by ClickHouse, holding logs, metrics, and traces from both environments. Grafana on prod SHALL be the only telemetry UI. Dev MUST NOT run a telemetry store or UI. The platform MUST NOT run VictoriaMetrics, VictoriaLogs, VictoriaTraces, Prometheus, HyperDX, or another parallel telemetry store or UI in either environment.

#### Scenario: Reconcile the platform definition
- **WHEN** both environments' Argo CD instances converge
- **THEN** prod runs the ClickHouse store, Grafana, and its ingest collector, dev runs only telemetry agents, and neither runs a Victoria component, Prometheus, or HyperDX

#### Scenario: Query across environments
- **WHEN** an operator searches logs, metrics, or traces in Grafana
- **THEN** results from dev and prod come from the same store and can be filtered by environment

### Requirement: Internal-only UI
The platform SHALL serve Grafana on prod at a fixed internal LoadBalancer address from prod's LoadBalancer pool, on port 80. The UI MUST NOT have a public hostname or a Cloudflare tunnel route. The UI SHALL support searching logs and traces, querying metrics, and navigating between a trace and its logs, and SHALL provide the OpenTelemetry logs, traces, and service dashboards and the ClickHouse health dashboards shipped with its ClickHouse data source plugin. The UI MUST require a login and MUST NOT allow self sign-up or anonymous access.

#### Scenario: Operator opens the UI
- **WHEN** an operator on the LAN opens the UI's internal address and logs in with the admin credential
- **THEN** Grafana loads with the ClickHouse data source as the default and the provisioned dashboards present

#### Scenario: Trace to logs
- **WHEN** an operator opens a trace whose spans share a trace ID with log records
- **THEN** the UI shows those log records

#### Scenario: Unauthenticated visitor
- **WHEN** a visitor on the LAN opens the UI without logging in or tries to create an account
- **THEN** the UI shows only the login page and no account is created

### Requirement: Single-replica store on a fixed node
The ClickHouse server and its coordination service SHALL each run as a single replica on one designated fixed prod Proxmox node, on that node's local disk. The store is not replicated or backed up; losing that node's disk loses stored telemetry.

#### Scenario: Designated node restarts
- **WHEN** the designated node reboots
- **THEN** the store is unavailable until the node returns, then resumes with its previous data

#### Scenario: Prod is rebuilt
- **WHEN** prod is destroyed and re-provisioned
- **THEN** the store starts empty and ingest resumes without manual steps

### Requirement: Store credentials from the secret store
Every credential used by the store, its UI, and the ingest endpoint SHALL be delivered through the cluster's Doppler secret store. No such credential MAY appear in Git or in Helm values.

#### Scenario: Inspect the repository
- **WHEN** a user reads the observability components in Git
- **THEN** no ClickHouse, Grafana, or ingest credential value appears

## ADDED Requirements

### Requirement: Stateless UI provisioned from Git
The UI SHALL keep no state that is not defined in Git or the secret store. Its data source, dashboards, and admin account MUST be provisioned when it starts, and it MUST NOT use a PersistentVolumeClaim. Restarting or rescheduling the UI SHALL lose only login sessions and edits made in the UI.

#### Scenario: UI pod restarts
- **WHEN** the UI pod is deleted and recreated on any prod node
- **THEN** the same data source and dashboards are present and the admin credential still logs in

#### Scenario: Dashboard changed in Git
- **WHEN** a dashboard definition is changed in Git and Argo CD syncs
- **THEN** the UI shows the changed dashboard without an import step

### Requirement: Bounded UI queries
Queries from the UI SHALL run as a read-only store user whose per-query memory and execution time are limited. A query that exceeds a limit MUST fail on its own without stopping the store or other queries.

#### Scenario: Expensive dashboard query
- **WHEN** a UI query needs more memory or time than the UI user's limits allow
- **THEN** that query returns an error in the UI, and the store keeps accepting inserts and other queries

#### Scenario: UI attempts a write
- **WHEN** a query from the UI tries to insert, alter, or drop data
- **THEN** the store rejects it
