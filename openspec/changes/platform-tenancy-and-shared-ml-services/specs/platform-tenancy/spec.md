## Purpose

Define how the platform declares application tenants and the namespaced-only boundary they deploy within, so every cluster-wide and shared resource has a single platform owner.

## ADDED Requirements

### Requirement: Declarative tenant registration
The platform SHALL declare each tenant in one inventory. Each entry SHALL give an id, a source repository and the purpose namespaces. Optionally it gives external-secret Doppler settings, object-access ServiceAccounts, model-gateway clients, a Langfuse project and a Kubeflow Profile owner. From that entry alone the platform SHALL create:
- the tenant's namespaces, labelled for the ambient mesh and pod security;
- the stores the tenant needs;
- one Argo CD AppProject;
- one root Application, in the tenant's primary namespace, that reconciles the tenant repository's environment entrypoint.

Registering a tenant MUST NOT require any manual `kubectl apply`, token copy or one-time bootstrap step.

#### Scenario: Fresh environment
- **WHEN** an environment is provisioned from empty state with the tenant inventory listing `gateway` and `marketplace`
- **THEN** both tenants' namespaces, declared stores, AppProjects and root Applications exist, and each root Application syncs from its tenant repository with no manual step

#### Scenario: Tenant removed from inventory
- **WHEN** a tenant entry is deleted and the platform reconciles
- **THEN** that tenant's root Application, AppProject, stores, object policies and namespaces are pruned

### Requirement: Tenant namespace naming
Each tenant's namespaces SHALL be named `<tenant>`, or `<tenant>-<purpose>` for each additional purpose. Platform services SHALL run only in platform-owned namespaces, never in a tenant namespace.

#### Scenario: No shared namespaces
- **WHEN** all applications are synced
- **THEN** no namespace holds both a platform-owned Application's resources and a tenant Application's resources

### Requirement: Namespaced-only tenant boundary
A tenant AppProject SHALL accept sources only from that tenant's repository, and SHALL accept Application objects only from the tenant's primary namespace. It SHALL allow destinations only in that tenant's namespaces, and SHALL allow no cluster-scoped resource kinds. Tenants SHALL NOT be able to create or change secret stores, `ResourceQuota`s or `LimitRange`s in their namespaces.

#### Scenario: Cluster-scoped resource rejected
- **WHEN** a tenant Application renders a `ClusterRole`, `ClusterSecretStore` or `ClusterTunnel`
- **THEN** Argo CD refuses to sync that resource and reports a project permission error

#### Scenario: Foreign namespace rejected
- **WHEN** a tenant Application targets a namespace outside its own set, such as `observability`, `istio-system` or another tenant's namespace
- **THEN** Argo CD refuses the sync

#### Scenario: Application in a foreign namespace
- **WHEN** a tenant Application object is created in `argo-cd` or in another tenant's namespace
- **THEN** Argo CD refuses to reconcile it under the tenant project

#### Scenario: Secret store reserved
- **WHEN** a tenant Application renders a `SecretStore` in its own namespace
- **THEN** Argo CD refuses that resource

### Requirement: Tenant integration through namespaced resources
Each platform service that tenants use SHALL accept tenant integration only through namespaced resources in the tenant's namespaces. These include `ExternalSecret`, `HTTPRoute`, `TunnelBinding`, operator instance resources (`Cluster`, `Kafka`, `ClickHouseInstallation`, `Redis`), monitoring scrape resources, and Kubeflow workload resources. Shared gateways SHALL admit routes only from namespaces the platform labels as tenant namespaces.

#### Scenario: Tenant publishes a public route
- **WHEN** a tenant creates a `TunnelBinding` or `HTTPRoute` in its own namespace that references a platform-owned tunnel or gateway
- **THEN** traffic reaches the tenant service without the tenant creating any cluster-scoped object

#### Scenario: Tenant metrics
- **WHEN** a tenant creates a pod scrape resource in its own namespace
- **THEN** platform monitoring collects its metrics without the tenant writing to the `observability` namespace
