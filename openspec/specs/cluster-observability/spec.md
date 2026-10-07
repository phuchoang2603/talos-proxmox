# cluster-observability Specification

## Purpose

Collect logs, metrics, traces, and Kubernetes events from the prod cluster into one ClickHouse store on prod, and make them searchable from an internal-only UI.

## Requirements

### Requirement: Single telemetry store in prod
The platform SHALL run exactly one telemetry store, on prod, backed by ClickHouse, holding prod's logs, metrics, and traces. Grafana on prod SHALL be the only telemetry UI. Dev MUST NOT run any telemetry component. The platform MUST NOT run VictoriaMetrics, VictoriaLogs, VictoriaTraces, Prometheus, HyperDX, or another parallel telemetry store or UI in either environment.

#### Scenario: Reconcile the platform definition
- **WHEN** both environments' Argo CD instances converge
- **THEN** prod runs the ClickHouse store, Grafana, its ingest collector, and its telemetry agents, dev runs no telemetry component, and neither runs a Victoria component, Prometheus, or HyperDX

#### Scenario: Search telemetry
- **WHEN** an operator searches logs, metrics, or traces in Grafana
- **THEN** results come from prod's store

### Requirement: Telemetry collection in prod
Prod SHALL collect container logs from every node, node and kubelet resource metrics, cluster object metrics, and Kubernetes events, and SHALL accept OTLP traces, metrics, and logs from applications at a stable in-cluster endpoint. Collection MUST include AWS burst workers while they exist. Collectors MUST NOT use PersistentVolumeClaims.

#### Scenario: Application sends OTLP
- **WHEN** a prod workload exports OTLP over gRPC or HTTP to the in-cluster telemetry endpoint
- **THEN** its traces, metrics, and logs appear in the store

#### Scenario: Pod writes to stdout
- **WHEN** a container on any fixed Proxmox node or AWS burst worker writes a log line
- **THEN** the line appears in the store with its namespace, pod, and container

#### Scenario: Cluster events and state
- **WHEN** a Kubernetes event is emitted or a node's resource usage changes
- **THEN** the event and the node, pod, and container metrics appear in the store

### Requirement: Telemetry source labels
Every stored log, metric, and span SHALL carry the Kubernetes cluster name and environment it came from, set by the collector rather than by applications.

#### Scenario: Collector labels telemetry
- **WHEN** a workload emits telemetry without cluster or environment attributes
- **THEN** it is stored with prod's cluster name and environment

### Requirement: In-cluster ingest only
The ingest collector SHALL be reachable only from inside prod's cluster. It MUST NOT have a LoadBalancer or LAN address, a public hostname, or a Cloudflare tunnel route. No ingest credential SHALL exist, and no other environment MAY send telemetry to it.

#### Scenario: Prod agent sends telemetry
- **WHEN** a prod agent exports telemetry to the ingest collector's in-cluster Service
- **THEN** the telemetry is stored

#### Scenario: Client on the LAN
- **WHEN** a host outside prod's cluster looks for an OTLP endpoint on prod
- **THEN** no LAN address accepts OTLP

### Requirement: Seven-day retention with bounded disk use
The store SHALL keep logs, metrics, and traces for 7 days and delete older data automatically. ClickHouse's own server logs and system log tables MUST also be bounded to 7 days or less. The store MUST stop accepting writes before its disk is completely full.

#### Scenario: Data ages out
- **WHEN** telemetry is older than 7 days
- **THEN** it is no longer stored or returned by queries, without manual cleanup

#### Scenario: Disk nearly full
- **WHEN** the store's disk reaches its reserved free-space threshold
- **THEN** new inserts fail visibly at the collector instead of the node's disk filling completely

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
Every credential used by the store and its UI SHALL be delivered through the cluster's Doppler secret store. No such credential MAY appear in Git or in Helm values.

#### Scenario: Inspect the repository
- **WHEN** a user reads the observability components in Git
- **THEN** no ClickHouse or Grafana credential value appears

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
