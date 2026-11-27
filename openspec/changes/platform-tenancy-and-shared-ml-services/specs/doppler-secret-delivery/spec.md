## ADDED Requirements

### Requirement: Doppler holds only externally originated secrets
Doppler SHALL be the single source for secrets that originate outside the cluster: third-party API tokens, identity-provider client secrets issued by external providers, human login credentials, infrastructure credentials, and credentials OpenTofu must emit (such as kubeconfig, talosconfig and autoscaler keys). Credentials used only between in-cluster components SHALL NOT be stored in Doppler. OpenTofu SHALL NOT copy a secret value from one Doppler project or config into another. Foundation SHALL be recreatable without imports of deleted resources. CI SHALL NOT write secrets through the Doppler CLI.

#### Scenario: Fresh foundation
- **WHEN** foundation is rebuilt from empty state
- **THEN** the platform configs and scoped tokens are created, no obsolete imports are required, and no internal credential is written to Doppler

#### Scenario: Cluster apply
- **WHEN** a cluster root is applied
- **THEN** only credentials it must emit for operators reach its Doppler config; only prod receives Autoscaler and CSI credentials

#### Scenario: Autoscaler key creation
- **WHEN** prod is applied from fresh state
- **THEN** its independent autoscaler service-account key is generated and stored in that environment's Doppler config without manual creation

#### Scenario: Retired component credentials
- **WHEN** a component that consumed an operator-entered secret is removed from the platform
- **THEN** its keys are deleted from the Doppler configs that held them

#### Scenario: Inventory of Doppler keys
- **WHEN** the dev platform config is listed
- **THEN** every key is either externally originated or emitted by OpenTofu, and none is a database, cache, salt, signing or internal API credential

### Requirement: Doppler secrets reach clusters only through stores
Every Kubernetes Secret derived from Doppler SHALL be produced by External Secrets Operator from a secret store, except the bootstrap authentication Secret of the platform store and the production autoscaler's GCP credential Secret, both of which the platform root creates. Each store's credential MUST be a read-only Doppler token scoped to exactly one project and config, and read-only Doppler tokens MUST be the only Doppler credentials in the cluster. The platform SHALL own one `ClusterSecretStore` for its own project, restricted to platform namespaces. Tenant stores are defined by `Tenant Doppler stores`.

#### Scenario: Bootstrap store authentication
- **WHEN** the platform root provisions a fresh environment before ESO is running
- **THEN** it creates only the platform store's token Secret, and every other Doppler-derived Secret is ESO-owned

#### Scenario: Platform store restricted
- **WHEN** an ExternalSecret in a tenant namespace references the platform `ClusterSecretStore`
- **THEN** ESO refuses it

#### Scenario: Autoscaler credential
- **WHEN** the platform root installs the autoscaler
- **THEN** it creates the production autoscaler's GCP credential Secret from the environment's Doppler config, and no ExternalSecret manages that Secret

#### Scenario: Store token scope
- **WHEN** a store's token is used to write, or to read a different project or config than the one it is scoped to
- **THEN** Doppler rejects the request

### Requirement: Tenant Doppler stores
A tenant SHALL have a Doppler project and token only if its inventory entry declares external secrets. For such a tenant, foundation SHALL issue one read-only `external-secrets` token per environment config. The platform SHALL deliver that token directly into a namespaced `SecretStore` named `doppler` in each tenant namespace that the inventory lists for it. No tenant store SHALL be cluster-wide, and tenant repositories SHALL NOT declare a store or a token manifest.

#### Scenario: Tenant without external secrets
- **WHEN** a tenant entry declares no external secrets
- **THEN** no Doppler project, token or store exists for it, and its workloads still start with their in-cluster credentials

#### Scenario: Tenant with external secrets
- **WHEN** a tenant entry declares external secrets
- **THEN** its listed namespaces each hold a ready `doppler` `SecretStore` reading only that tenant's config, and no `ClusterSecretStore` exists for the tenant

#### Scenario: Consumer store token scope
- **WHEN** a tenant store's token is used to read another tenant's project, the platform project, or to write
- **THEN** Doppler rejects the request

### Requirement: In-cluster credential generation
Credentials used only between in-cluster components SHALL be generated in the cluster. A component SHALL use its operator's native credential generation where one exists, for example CNPG application and managed-role secrets or Strimzi `KafkaUser` secrets. Otherwise it SHALL use an ESO generator owned by the namespace that consumes the credential. Generated credentials SHALL NOT be written to Doppler. A credential that protects data outliving the cluster SHALL be pushed to Doppler with ESO `PushSecret` and read back from there on rebuild.

#### Scenario: Database password
- **WHEN** a component's CNPG database is created on a fresh cluster
- **THEN** its connection Secret is generated by CNPG or an ESO generator in the component namespace, and no Doppler key holds it

#### Scenario: Retained-data key
- **WHEN** a component declares an encryption key for data retained across rebuilds
- **THEN** the key is generated once, pushed to Doppler, and the same value is restored after the environment is rebuilt

### Requirement: Cross-namespace credential delivery
When a platform service issues a credential that a tenant consumes, such as Langfuse project keys, the platform SHALL deliver it with an ESO `kubernetes` provider `SecretStore` that the platform owns in the tenant namespace. That store SHALL be authorized by a Role restricted to the named source Secrets. Tenants SHALL NOT be able to read any other Secret in the platform namespace.

#### Scenario: Tenant reads its Langfuse keys
- **WHEN** an ExternalSecret in `gateway-llm` references the platform-owned `langfuse` store for the gateway project keys
- **THEN** the keys are copied into `gateway-llm`

#### Scenario: Tenant reads another Secret
- **WHEN** that ExternalSecret references any other Secret in `langfuse`
- **THEN** the read is denied and the failure appears on the ExternalSecret status

## REMOVED Requirements

### Requirement: Doppler as the single secret source
**Reason**: Doppler no longer stores generated internal credentials; they are generated in the cluster.
**Migration**: Replaced by `Doppler holds only externally originated secrets` and `In-cluster credential generation`. Internal keys are deleted from Doppler on rebuild.

### Requirement: Clusters receive secrets only through the secret store
**Reason**: Per-consumer `ClusterSecretStore`s are removed.
**Migration**: Replaced by `Doppler secrets reach clusters only through stores` and `Tenant Doppler stores`.

### Requirement: Consumer secret-store provisioning
**Reason**: Consumer tokens in `kube-system` and cluster-wide consumer stores are removed; tenants without external secrets get no Doppler project.
**Migration**: Replaced by `Tenant Doppler stores`.
