## MODIFIED Requirements

### Requirement: Scoped workload access
Object consumers SHALL access storage only through per-ServiceAccount identities as defined by `workload-object-identity`, independent of CI, autoscaler, CSI and worker instance identities. Credential values SHALL NOT appear in Git or routine logs.

#### Scenario: Outside bucket access
- **WHEN** a consumer requests an object outside its authorized buckets
- **THEN** the request is denied

#### Scenario: Worker instance attempts S3 access
- **WHEN** access uses only the worker instance identity
- **THEN** no dataset or artifact access is granted

#### Scenario: Workload exceeds its scope
- **WHEN** a workload's credentials access an unauthorized prefix or bucket
- **THEN** the object store denies the request

### Requirement: Consumer storage handoff
Both environments SHALL expose bucket, region, endpoint, STS endpoint and prefix configuration to workloads as non-secret configuration. Prod paths MUST NOT point at dev storage. Object storage readiness SHALL NOT imply dataset completeness. No object credential SHALL be handed to a consumer through Doppler.

#### Scenario: Prod storage configuration
- **WHEN** a prod consumer starts
- **THEN** its object paths use prod storage without home storage dependencies

#### Scenario: Consumer object credential delivery
- **WHEN** a consumer workload needs object access
- **THEN** it obtains credentials by exchanging its own ServiceAccount token, and no ExternalSecret or Doppler key holds an object credential

#### Scenario: Bucket exists before export
- **WHEN** infrastructure is ready but export data is absent
- **THEN** the handoff reports storage availability without claiming the training dataset is ready

#### Scenario: Optional replication transport
- **WHEN** RustFS-to-GCS replication is enabled
- **THEN** version compatibility and directional transfer are verified and consumers still require destination completeness checks
