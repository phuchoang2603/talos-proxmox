## MODIFIED Requirements

### Requirement: Consumer-owned storage integration
The platform SHALL own Polaris service installation, authentication and durable catalog database state, and SHALL run Polaris only in the platform `polaris` namespace. No tenant chart SHALL install Polaris. Polaris SHALL reach storage through its own workload object identity. The platform SHALL generate each tenant's catalog principal in the cluster and deliver it through cross-namespace credential delivery. Tenant engines SHALL read table files through their own workload object identities. Tenants SHALL own catalog and warehouse registration and engine-specific SQL catalog integration, performed from their own namespaces. The platform SHALL NOT register a tenant warehouse.

#### Scenario: Reconcile platform before a consumer
- **WHEN** the platform is reconciled without a tenant integration
- **THEN** Polaris is ready in `polaris` and no tenant catalog, warehouse or SQL reader exists

#### Scenario: Tenant registers its warehouse
- **WHEN** the gateway's registration job runs in `gateway-data` with its delivered principal
- **THEN** its catalog is registered against its own storage prefix, and no Polaris workload runs in a tenant namespace
