## MODIFIED Requirements

### Requirement: Private regional staging storage
Prod SHALL use generic private encrypted versioned S3 storage with lakehouse, datasets, artifacts, runs and backups prefixes. Dev SHALL use existing MinIO without a dev S3 bucket. Retention SHALL preserve active table data and checkpoints. Optional image assets SHALL be separately owned and disabled when unused.

#### Scenario: Run cleanup
- **WHEN** finished run objects expire
- **THEN** lakehouse metadata and data files remain intact

#### Scenario: Training node is removed
- **WHEN** an AWS worker terminates
- **THEN** completed dataset exports and checkpoints remain available independently of that node

#### Scenario: Retention cleanup
- **WHEN** an object is referenced by an active run or pinned candidate
- **THEN** staging cleanup does not delete it before its declared retention obligation ends

### Requirement: Scoped workload access
Object consumers SHALL use purpose-scoped credentials independent of CI, autoscaler, CSI and permissionless worker roles. Secret values SHALL NOT appear in Git or routine logs.

#### Scenario: Outside prefix access
- **WHEN** a consumer requests an object outside its authorized prefixes
- **THEN** the request is denied

#### Scenario: Worker instance attempts S3 access
- **WHEN** access uses only the worker instance identity
- **THEN** no dataset or artifact access is granted

#### Scenario: Workload exceeds its scope
- **WHEN** a purpose-scoped credential accesses an unauthorized prefix or bucket
- **THEN** AWS denies the request

### Requirement: Consumer storage handoff
Both environments SHALL expose bucket, region, endpoint and prefix configuration through a common contract with private credentials. Prod paths MUST NOT point at dev MinIO. Object storage readiness SHALL NOT imply dataset completeness.

#### Scenario: Prod storage configuration
- **WHEN** a prod consumer starts
- **THEN** its object paths use prod S3 without home MinIO dependencies

#### Scenario: Bucket exists before export
- **WHEN** infrastructure is ready but export data is absent
- **THEN** the handoff reports storage availability without claiming the training dataset is ready

#### Scenario: Optional replication transport
- **WHEN** RustFS-to-S3 replication is enabled
- **THEN** version compatibility and directional transfer are verified and consumers still require destination completeness checks
