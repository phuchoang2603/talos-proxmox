## Purpose

Give every workload that touches object storage its own short-lived credentials, derived from its Kubernetes ServiceAccount, so no static object key exists in Git, Doppler or a Kubernetes Secret.

## ADDED Requirements

### Requirement: Stable public service-account issuer
Each cluster SHALL issue ServiceAccount tokens under a stable HTTPS issuer URL that does not change when the cluster is rebuilt. Its OpenID discovery document and JWKS SHALL be reachable by the object store without trusting the cluster CA and without authentication.

#### Scenario: Discovery after rebuild
- **WHEN** dev is destroyed and re-provisioned
- **THEN** the issuer URL is unchanged, and its discovery document serves the new cluster's signing keys

### Requirement: Per-ServiceAccount object policy
The platform SHALL declare object access per ServiceAccount, as a list of bucket prefixes and read or write mode, in the tenant inventory for tenant workloads and in component values for platform workloads. Foundation SHALL create exactly one object-store policy for each declared ServiceAccount. A workload SHALL receive no object access unless its ServiceAccount has a declared policy.

#### Scenario: Declared workload
- **WHEN** the gateway Spark ServiceAccount in `gateway-data` exchanges its projected token at the STS endpoint
- **THEN** it receives temporary credentials that can read and write only its declared prefixes

#### Scenario: Undeclared workload
- **WHEN** a ServiceAccount without a declared policy exchanges its token
- **THEN** the STS request is rejected

#### Scenario: Prefix outside scope
- **WHEN** a workload's temporary credentials access another workload's prefix
- **THEN** the object store denies the request

### Requirement: Short-lived credentials only
Workloads SHALL obtain object credentials only through web-identity token exchange, using a projected token with a dedicated object-store audience. Credentials SHALL expire within the token and session lifetime and SHALL be refreshed by the client. No static object access key SHALL exist for any workload, and object keys SHALL NOT be stored in Doppler, Git or Kubernetes Secrets. The only static object-store credential SHALL be the operator root credential that foundation uses.

#### Scenario: No static keys
- **WHEN** all applications are synced
- **THEN** no Kubernetes Secret and no Doppler config contains an object-store access key other than foundation's root credential

#### Scenario: Token from another audience
- **WHEN** a workload presents its default API-server-audience token to the STS endpoint
- **THEN** the exchange is rejected
