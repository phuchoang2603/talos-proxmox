## Purpose

Collect logs, metrics, traces, and Kubernetes events from the dev and prod clusters into one ClickHouse store on prod, and make them searchable from an internal-only UI.

## ADDED Requirements

### Requirement: Single telemetry store on prod
The platform SHALL run exactly one telemetry store, on prod, backed by ClickHouse, holding logs, metrics, and traces from both environments. Dev MUST NOT run a telemetry store or UI. The platform MUST NOT run VictoriaMetrics, VictoriaLogs, VictoriaTraces, Prometheus, Grafana, or another parallel telemetry store in either environment.

#### Scenario: Reconcile the platform definition
- **WHEN** both environments' Argo CD instances converge
- **THEN** prod runs the ClickHouse store, its UI, and its ingest collector, dev runs only telemetry agents, and neither runs a Victoria component or Grafana

#### Scenario: Query across environments
- **WHEN** an operator searches logs, metrics, or traces in the UI
- **THEN** results from dev and prod come from the same store and can be filtered by environment

### Requirement: Telemetry collection in every environment
Each environment SHALL collect container logs from every node, node and kubelet resource metrics, cluster object metrics, and Kubernetes events, and SHALL accept OTLP traces, metrics, and logs from applications at a stable in-cluster endpoint. Collection MUST include AWS burst workers while they exist. Collectors MUST NOT use PersistentVolumeClaims.

#### Scenario: Application sends OTLP
- **WHEN** a workload in dev or prod exports OTLP over gRPC or HTTP to the in-cluster telemetry endpoint
- **THEN** its traces, metrics, and logs appear in the prod store

#### Scenario: Pod writes to stdout
- **WHEN** a container on any fixed Proxmox node or AWS burst worker writes a log line
- **THEN** the line appears in the prod store with its namespace, pod, and container

#### Scenario: Cluster events and state
- **WHEN** a Kubernetes event is emitted or a node's resource usage changes
- **THEN** the event and the node, pod, and container metrics appear in the prod store

### Requirement: Source identification
Every stored log, metric, and span SHALL carry the Kubernetes cluster name and the environment (`dev` or `prod`) it came from, set by the collecting environment rather than by applications.

#### Scenario: Same workload name in both environments
- **WHEN** dev and prod both run a workload with the same namespace and name
- **THEN** their telemetry can be told apart by cluster name and environment

### Requirement: Authenticated cross-environment ingest
Prod SHALL expose an OTLP ingest endpoint on an internal LAN address from its LoadBalancer pool, reachable from dev nodes. The endpoint MUST reject requests that do not present the ingest credential, and MUST NOT be exposed through the Cloudflare tunnel or any public address. Dev MUST send telemetry only through this endpoint and MUST hold no other credential for prod.

#### Scenario: Dev agent sends telemetry
- **WHEN** a dev agent exports telemetry to prod's ingest endpoint with the ingest credential
- **THEN** prod accepts it and stores it

#### Scenario: Unauthenticated request
- **WHEN** a client sends OTLP to prod's ingest endpoint without the ingest credential or with a wrong one
- **THEN** the request is rejected and nothing is stored

#### Scenario: Prod ingest is unavailable
- **WHEN** prod's ingest endpoint or store is unreachable
- **THEN** dev keeps running and converging, dev agents buffer telemetry for a bounded period, and data beyond that buffer is dropped rather than exhausting dev resources

### Requirement: Seven-day retention with bounded disk use
The store SHALL keep logs, metrics, and traces for 7 days and delete older data automatically. ClickHouse's own server logs and system log tables MUST also be bounded to 7 days or less. The store MUST stop accepting writes before its disk is completely full.

#### Scenario: Data ages out
- **WHEN** telemetry is older than 7 days
- **THEN** it is no longer stored or returned by queries, without manual cleanup

#### Scenario: Disk nearly full
- **WHEN** the store's disk reaches its reserved free-space threshold
- **THEN** new inserts fail visibly at the collector instead of the node's disk filling completely

### Requirement: Internal-only UI
The platform SHALL serve the telemetry UI on prod at a fixed internal Gateway address from prod's LoadBalancer pool. The UI MUST NOT have a public hostname or a Cloudflare tunnel route. The UI SHALL support searching logs, traces, and metrics and navigating between a trace and its logs.

#### Scenario: Operator opens the UI
- **WHEN** an operator on the LAN opens the UI's internal address
- **THEN** HyperDX loads and shows the dev and prod log, trace, and metric sources

#### Scenario: Trace to logs
- **WHEN** an operator opens a trace whose spans share a trace ID with log records
- **THEN** the UI shows those log records

### Requirement: Single-replica store on a fixed node
The ClickHouse server and its coordination service SHALL each run as a single replica on one designated fixed prod Proxmox node, on that node's local disk. The store is not replicated or backed up; losing that node's disk loses stored telemetry. The UI's metadata store MUST use persistent storage on a fixed Proxmox node.

#### Scenario: Designated node restarts
- **WHEN** the designated node reboots
- **THEN** the store is unavailable until the node returns, then resumes with its previous data

#### Scenario: Prod is rebuilt
- **WHEN** prod is destroyed and re-provisioned
- **THEN** the store starts empty and ingest resumes without manual steps

### Requirement: Store credentials from the secret store
Every credential used by the store, its UI, its metadata store, and the ingest endpoint SHALL be delivered through the cluster's Doppler secret store. No such credential MAY appear in Git or in Helm values.

#### Scenario: Inspect the repository
- **WHEN** a user reads the observability components in Git
- **THEN** no ClickHouse, MongoDB, HyperDX, or ingest credential value appears
