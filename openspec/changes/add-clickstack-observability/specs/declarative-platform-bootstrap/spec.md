## MODIFIED Requirements

### Requirement: Self-contained environments
The platform SHALL consist only of the `dev` and `prod` environments. Each MUST run its own Argo CD, which manages only its own cluster. An environment MUST NOT hold credentials for, depend on, or be ordered after another environment or a separate management cluster, with one exception: dev MAY hold the write-only telemetry ingest credential for prod's ingest endpoint. That credential MUST NOT grant read access to prod telemetry or any other access to prod, and dev MUST converge whether or not prod is reachable.

#### Scenario: Provision one environment alone
- **WHEN** only prod is provisioned from fresh state
- **THEN** prod reaches a fully synced platform without dev existing

#### Scenario: Provision dev without prod
- **WHEN** dev is provisioned while prod does not exist or is unreachable
- **THEN** dev reaches a fully synced platform, and only its telemetry export fails

#### Scenario: Lose one environment
- **WHEN** the dev cluster is destroyed
- **THEN** prod's Argo CD, applications, and secrets are unaffected

#### Scenario: Cross-environment access
- **WHEN** a cluster's Argo CD or secret store is inspected
- **THEN** it holds no credentials for the other environment, except dev's write-only telemetry ingest credential for prod
