## REMOVED Requirements

### Requirement: Single telemetry store on prod
**Reason**: Dev no longer sends telemetry to prod, so the store no longer holds dev data and cross-environment queries no longer apply.
**Migration**: Replaced by "Single telemetry store in prod".

### Requirement: Telemetry collection in every environment
**Reason**: Dev runs no telemetry collectors.
**Migration**: Replaced by "Telemetry collection in prod".

### Requirement: Source identification
**Reason**: Telemetry no longer comes from more than one environment, so telling environments apart is no longer a requirement.
**Migration**: Replaced by "Telemetry source labels", which keeps the labels for every stored record.

### Requirement: Authenticated cross-environment ingest
**Reason**: Dev was the only client outside prod. Without it, the gateway needs no LAN address or ingest credential.
**Migration**: Replaced by "In-cluster ingest only". Delete the ingest token from Doppler.

## ADDED Requirements

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
