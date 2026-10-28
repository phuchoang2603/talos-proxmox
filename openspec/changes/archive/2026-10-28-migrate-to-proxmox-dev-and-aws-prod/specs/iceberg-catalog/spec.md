## Purpose

Provide a shared Iceberg REST interface with independent durable catalog state and object storage in each environment.

## ADDED Requirements

### Requirement: Environment-local durable REST catalog
Both environments SHALL expose authenticated Iceberg REST catalogs with durable PostgreSQL registration and commit state. Dev files SHALL use MinIO and prod files SHALL use S3. Catalog restart SHALL preserve registrations. All catalog databases SHALL initially use one CNPG instance.

#### Scenario: Restart catalog
- **WHEN** the catalog restarts after a successful commit
- **THEN** tables remain registered and readable without rebuilding metadata

### Requirement: Cross-engine compatibility
Pinned catalog and client versions SHALL pass Spark, Flink and StarRocks read/commit acceptance before readiness is claimed. Table data, manifests and metadata JSON SHALL remain in object storage.

#### Scenario: Engine handoff
- **WHEN** one supported engine commits a table
- **THEN** another supported engine reads the committed rows through the catalog
