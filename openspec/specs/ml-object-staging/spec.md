# ml-object-staging Specification

## Purpose
Provide private, versioned cloud object storage and scoped workload access for immutable training exports, checkpoints and candidate artifacts.

## Requirements

### Requirement: Private regional staging storage
The platform SHALL provision versioned, encrypted S3 storage in the training region with public access blocked. Dataset, checkpoint and output prefixes SHALL have declared retention policies that preserve active or pinned objects. Node-local scratch SHALL remain disposable.

#### Scenario: Training node is removed
- **WHEN** an AWS worker terminates
- **THEN** completed dataset exports and checkpoints remain available independently of that node

#### Scenario: Retention cleanup
- **WHEN** an object is referenced by an active run or pinned candidate
- **THEN** staging cleanup does not delete it before its declared retention obligation ends

### Requirement: Scoped workload access
Storage access SHALL use a single workload credential separate from Karpenter, CI and the permissionless EC2 worker role, limited to the dataset and run prefixes of the staging bucket. Secret values SHALL NOT be committed or emitted in routine logs.

#### Scenario: Worker instance attempts S3 access
- **WHEN** access uses only the worker instance identity
- **THEN** no dataset or artifact access is granted

#### Scenario: Workload exceeds its scope
- **WHEN** the workload credential reads or writes outside the dataset and run prefixes of the staging bucket, or in another bucket
- **THEN** access is denied

### Requirement: Consumer storage handoff
The platform SHALL expose non-secret bucket, region, endpoint and prefix-policy configuration plus a private credential-delivery contract. Storage provisioning SHALL NOT imply dataset completeness or synchronize a live lake catalog; consumers SHALL verify exported object inventories and hashes.

#### Scenario: Bucket exists before export
- **WHEN** infrastructure is ready but export data is absent
- **THEN** the handoff reports storage availability without claiming the training dataset is ready

#### Scenario: Optional replication transport
- **WHEN** RustFS-to-S3 replication is enabled
- **THEN** version compatibility and directional transfer are verified and consumers still require destination completeness checks
