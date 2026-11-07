## MODIFIED Requirements

### Requirement: Consumer storage handoff
Both environments SHALL expose bucket, region, endpoint and prefix configuration through a common contract with private credentials. Prod paths MUST NOT point at dev MinIO. Object storage readiness SHALL NOT imply dataset completeness.

Each application consumer's scoped object-storage credentials SHALL be delivered through that consumer's own Doppler project and secret store, not the platform's. The platform object-storage provisioner SHALL write a consumer's purpose-scoped keys into the consumer's Doppler project under key names the consumer reads directly, so that no consumer ExternalSecret references the platform's Doppler project or store for object credentials.

#### Scenario: Prod storage configuration
- **WHEN** a prod consumer starts
- **THEN** its object paths use prod GCS without home MinIO dependencies

#### Scenario: Consumer object credential delivery
- **WHEN** a consumer workload reads its object-storage access key
- **THEN** the key is resolved from the consumer's own Doppler project through the consumer's platform-owned store, and no consumer ExternalSecret references the platform project for object credentials

#### Scenario: Bucket exists before export
- **WHEN** infrastructure is ready but export data is absent
- **THEN** the handoff reports storage availability without claiming the training dataset is ready

#### Scenario: Optional replication transport
- **WHEN** RustFS-to-GCS replication is enabled
- **THEN** version compatibility and directional transfer are verified and consumers still require destination completeness checks
