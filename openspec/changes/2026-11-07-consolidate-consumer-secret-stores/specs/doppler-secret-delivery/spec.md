## MODIFIED Requirements

### Requirement: Clusters receive secrets only through the secret store
Every Kubernetes Secret derived from Doppler SHALL be produced by External Secrets Operator from a secret store, except the bootstrap authentication Secret required by each store and the production autoscaler's GCP credential Secret. The platform root SHALL create and own every store authentication Secret and the autoscaler credential Secret; ESO MUST NOT also manage them. Each store's credential MUST be a read-only Doppler token scoped to exactly one project and config, and read-only Doppler tokens MUST be the only Doppler credentials placed in the cluster. No provisioning step outside the platform root MAY create a Secret from secret values.

The platform SHALL own one `ClusterSecretStore` per Doppler project consumed in the cluster: the platform's own project, and one per application consumer. Each consumer store SHALL be scoped by namespace conditions to that consumer's namespaces, and authenticated by a read-only token for that consumer's Doppler project. A consumer SHALL NOT declare its own store or provision its own store token; it references a platform-owned store by name.

#### Scenario: Bootstrap store authentication
- **WHEN** the platform root provisions a fresh environment before ESO is running
- **THEN** it creates each store's read-only token Secret in `kube-system` from the matching `ESO_*_DOPPLER_TOKEN`, and all application Secrets other than the autoscaler credential remain ESO-owned

#### Scenario: Consumer store ownership
- **WHEN** an application consumer is deployed by its own Argo CD
- **THEN** no store or `doppler-token` Secret is created by the consumer, and its ExternalSecrets resolve against a platform-owned `ClusterSecretStore` scoped to that consumer's namespaces

#### Scenario: Autoscaler credential
- **WHEN** the platform root installs the autoscaler
- **THEN** it creates the production autoscaler's GCP credential Secret from the environment's Doppler config, and no ExternalSecret manages that Secret

#### Scenario: Application secret
- **WHEN** the Cloudflare tunnel, observability, or telemetry agent component is synced by Argo CD
- **THEN** its Secrets are created by ExternalSecrets from the Doppler store, and no workflow writes those Secrets directly

#### Scenario: Store token scope
- **WHEN** a store's token is used to write, or to read a different project or config than the one it is scoped to
- **THEN** Doppler rejects the request

## ADDED Requirements

### Requirement: Consumer secret-store provisioning
Foundation SHALL issue one read-only `external-secrets` service token per application-consumer Doppler project and config, and SHALL publish each token into the platform's own config as a distinctly named `ESO_<CONSUMER>_DOPPLER_TOKEN`. The platform root SHALL consume those values to create one `kube-system/<consumer>-doppler-token` Secret per consumer. Consumer repositories SHALL NOT contain a secret-store chart or a hand-applied `doppler-token` manifest.

#### Scenario: Consumer token issuance
- **WHEN** foundation is applied
- **THEN** a read-only token exists for each consumer project and config, and the platform config holds the corresponding `ESO_<CONSUMER>_DOPPLER_TOKEN` values, shown as sensitive in plan output

#### Scenario: Consumer token Secret
- **WHEN** the platform root is applied
- **THEN** each consumer's `<consumer>-doppler-token` Secret exists in `kube-system`, created from its `ESO_<CONSUMER>_DOPPLER_TOKEN`, and no consumer-side manifest provides that Secret

#### Scenario: Consumer store token scope
- **WHEN** a consumer store's token is used to read another consumer's project, the platform project, or to write
- **THEN** Doppler rejects the request
