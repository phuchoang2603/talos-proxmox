## MODIFIED Requirements

### Requirement: Single telemetry store in prod
The platform SHALL run VictoriaMetrics for metrics, VictoriaLogs for logs, and VictoriaTraces for traces in prod using victoria-metrics-k8s-stack. Grafana SHALL be the telemetry UI. Dev SHALL run the same telemetry components with minimal replicas and bounded activity. The platform MUST NOT run ClickHouse, HyperDX, or their operators, credentials, or archive jobs. Existing telemetry MAY be discarded during replacement.

#### Scenario: Reconcile the platform definition
- **WHEN** both environments' Argo CD instances converge
- **THEN** prod runs the Victoria stores, Grafana, VMAgent, VTAgent, and VLAgent, dev runs an independent equivalent stack, and neither runs ClickHouse or HyperDX

#### Scenario: Search telemetry
- **WHEN** an operator searches logs, metrics, or traces in Grafana
- **THEN** results come from their own environment store



### Requirement: Telemetry collection in prod
Each environment SHALL collect container logs from every node, node and kubelet resource metrics, cluster object metrics, and SHALL accept OTLP traces, cumulative metrics, and logs from applications at separate in-cluster HTTP endpoints. Collection MUST include AWS burst workers while they exist. VMAgent and VTAgent SHALL accept application metrics and traces, remote-write them to their respective stores, and buffer pending writes on separate persistent volumes using the environment storage class. Each queue SHALL be bounded to 513 MiB per destination, survive pod restarts, and replay when the store recovers. VLAgent SHALL collect container logs. The platform MUST NOT run OpenTelemetry collectors or gateways.

#### Scenario: Application sends OTLP
- **WHEN** a prod workload exports OTLP over HTTP/protobuf to the matching in-cluster signal endpoint
- **THEN** its traces, metrics, and logs appear in the store

#### Scenario: Pod writes to stdout
- **WHEN** a container on any fixed Proxmox node or AWS burst worker writes a log line
- **THEN** the line appears in the store with its namespace, pod, and container

#### Scenario: Cluster state
- **WHEN** a node's resource usage changes
- **THEN** the node, pod, and container metrics appear in the store



### Requirement: Telemetry source labels
Agents SHALL label collected logs and scraped metrics with their own cluster and environment. Applications SHALL set the cluster and environment resource attributes when exporting directly.

#### Scenario: Telemetry source labels
- **WHEN** an agent collects telemetry or a workload exports it
- **THEN** it is stored with their own cluster name and environment



### Requirement: In-cluster ingest only
The ingest endpoints SHALL be reachable only from inside prod's cluster. It MUST NOT have a LoadBalancer or LAN address, a public hostname, or a Cloudflare tunnel route. No ingest credential SHALL exist, and no other environment MAY send telemetry to it.

#### Scenario: Prod agent sends telemetry
- **WHEN** a prod agent or workload exports telemetry to the appropriate in-cluster Service
- **THEN** the telemetry is stored

#### Scenario: Client on the LAN
- **WHEN** a host outside prod's cluster looks for an OTLP endpoint on prod
- **THEN** no LAN address accepts OTLP



### Requirement: Three-day retention with bounded disk use
The stores SHALL keep logs, metrics, and traces for 3 days and delete older data automatically. Each store MUST reserve free disk space and stop accepting writes before the node's disk is completely full. Telemetry SHALL NOT be archived to S3; the old Doppler archive credentials SHALL be deleted, and RustFS bucket, identity, and policy cleanup SHALL be handled by the operator.

#### Scenario: Data ages out
- **WHEN** telemetry is older than 3 days
- **THEN** it is no longer stored or returned by queries, without manual cleanup

#### Scenario: Disk nearly full
- **WHEN** the store's disk reaches its reserved free-space threshold
- **THEN** new inserts fail visibly at the exporter instead of the node's disk filling completely



### Requirement: Telemetry UI access
The platform SHALL serve Grafana in both environments at their own public hostnames through their own tunnels and internally through ClusterIP Services. Both environments SHALL support management port-forward and SHALL NOT provision UI LoadBalancer Services. The UI SHALL support searching logs and traces, querying metrics, and navigating between a trace and its logs, and SHALL provide the Kubernetes and Victoria dashboards shipped with the stack. The UI MUST require a login through Dex or with the admin password at both addresses. It MUST NOT allow anonymous access or password sign-up, and it MUST create accounts only for Dex identities it maps to a role.

#### Scenario: Operator opens the UI
- **WHEN** an operator uses the UI through management port-forward and logs in with the admin credential
- **THEN** Grafana loads with VictoriaMetrics as the default data source and VictoriaLogs and VictoriaTraces configured and the provisioned dashboards present

#### Scenario: Operator opens the UI remotely
- **WHEN** the operator opens `https://grafana.phuchoang.sbs` and logs in through Dex
- **THEN** Grafana loads with the same data source and dashboards

#### Scenario: Trace to logs
- **WHEN** an operator opens a trace whose spans share a trace ID with log records
- **THEN** the UI shows those log records

#### Scenario: Unauthenticated visitor
- **WHEN** a visitor opens either address without logging in or tries to create an account with a password
- **THEN** the UI shows only the login page and no account is created



### Requirement: Single-replica store on a fixed node
VictoriaMetrics, VictoriaLogs, and VictoriaTraces SHALL each run as a single replica on the PVC-selected node with separate volumes using the environment storage class. The store is not replicated or backed up; losing that node's disk loses stored telemetry.

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
- **THEN** no Grafana credential value appears



### Requirement: UI provisioned from Git
The UI's data sources, dashboards, and admin account SHALL be provisioned from Git or the secret store. Grafana SHALL use a PersistentVolumeClaim using the environment storage class on the PVC-selected node for its application state.

#### Scenario: UI pod restarts
- **WHEN** the UI pod is deleted and recreated on the PVC-selected node
- **THEN** the same data source and dashboards are present and the admin credential still logs in

#### Scenario: Dashboard changed in Git
- **WHEN** a dashboard definition is changed in Git and Argo CD syncs
- **THEN** the UI shows the changed dashboard without an import step



### Requirement: Bounded UI queries
The UI SHALL use the stores' query APIs, with bounded query execution time and concurrent query limits. A query that exceeds a limit MUST fail on its own without stopping the store or other queries.

#### Scenario: Expensive dashboard query
- **WHEN** a UI query needs more memory or time than the UI user's limits allow
- **THEN** that query returns an error in the UI, and the store keeps accepting inserts and other queries

#### Scenario: UI attempts a write
- **WHEN** a query from the UI attempts a write through a query endpoint
- **THEN** the store rejects it
