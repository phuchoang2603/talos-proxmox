## RENAMED Requirements

- FROM: `### Requirement: Internal-only UI`
- TO: `### Requirement: Telemetry UI access`

## MODIFIED Requirements

### Requirement: Telemetry UI access
The platform SHALL serve Grafana on prod at a fixed internal LoadBalancer address from prod's LoadBalancer pool, on port 80, and at the public hostname `grafana.phuchoang.sbs` through prod's Cloudflare tunnel. The UI SHALL support searching logs and traces, querying metrics, and navigating between a trace and its logs, and SHALL provide the OpenTelemetry logs, traces, and service dashboards and the ClickHouse health dashboards shipped with its ClickHouse data source plugin. The UI MUST require a login through Dex or with the admin password at both addresses. It MUST NOT allow anonymous access or password sign-up, and it MUST create accounts only for Dex identities it maps to a role.

#### Scenario: Operator opens the UI
- **WHEN** an operator on the LAN opens the UI's internal address and logs in with the admin credential
- **THEN** Grafana loads with the ClickHouse data source as the default and the provisioned dashboards present

#### Scenario: Operator opens the UI remotely
- **WHEN** the operator opens `https://grafana.phuchoang.sbs` and logs in through Dex
- **THEN** Grafana loads with the same data source and dashboards

#### Scenario: Trace to logs
- **WHEN** an operator opens a trace whose spans share a trace ID with log records
- **THEN** the UI shows those log records

#### Scenario: Unauthenticated visitor
- **WHEN** a visitor opens either address without logging in or tries to create an account with a password
- **THEN** the UI shows only the login page and no account is created
