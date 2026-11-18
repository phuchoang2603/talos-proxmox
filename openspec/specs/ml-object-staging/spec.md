# ml-object-staging Specification

## Purpose
Provide private, versioned cloud object storage and scoped workload access for immutable training exports, checkpoints and candidate artifacts.

## Requirements

### Requirement: Private regional staging storage
Prod SHALL use one private encrypted versioned GCS object bucket shared by training, gateway, artifacts and Substrate, exposed through the XML/S3 compatibility API with purpose-scoped HMAC credentials. Its top-level prefixes SHALL match dev MinIO: artifacts/, datasets/, lakehouse/, runs/ and substrate/. Artifact object access SHALL be restricted to artifacts/, datasets/ and runs/; Substrate object access SHALL be restricted to substrate/. Bucket listing MAY expose object names outside those prefixes. Dev SHALL use existing MinIO without cloud object buckets. Retention SHALL preserve active table data and checkpoints. Talos GCE image assets SHALL be separately owned by foundation. Run objects SHALL remain retained until explicit application cleanup; S3 object-tag lifecycle rules SHALL NOT be assumed available.

#### Scenario: Run cleanup
- **WHEN** finished run objects expire
- **THEN** lakehouse metadata and data files remain intact

#### Scenario: Training node is removed
- **WHEN** a GCP worker terminates
- **THEN** completed dataset exports and checkpoints remain available independently of that node

#### Scenario: Retention cleanup
- **WHEN** an object is referenced by an active run or pinned candidate
- **THEN** staging cleanup does not delete it before its declared retention obligation ends

### Requirement: Scoped workload access
Object consumers SHALL use purpose-scoped credentials independent of CI, autoscaler, CSI and permissionless worker roles. Secret values SHALL NOT appear in Git or routine logs.

#### Scenario: Outside bucket access
- **WHEN** a consumer requests an object outside its authorized buckets
- **THEN** the request is denied

#### Scenario: Worker instance attempts S3 access
- **WHEN** access uses only the worker instance identity
- **THEN** no dataset or artifact access is granted

#### Scenario: Workload exceeds its scope
- **WHEN** a purpose-scoped credential accesses an unauthorized prefix or bucket
- **THEN** GCP denies the request

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
