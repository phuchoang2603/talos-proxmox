# doppler-secret-delivery Specification

## Purpose

Make Doppler the single source for platform secrets. OpenTofu writes generated credentials to it, and each cluster receives only its own environment's secrets through External Secrets Operator.

## Requirements

### Requirement: Doppler as the single secret source
The platform SHALL store generated and operator-issued credentials in the matching dev/prod Doppler config. Foundation SHALL be recreatable without imports of deleted resources and generate application credentials for both environments. Cluster roots SHALL generate only credentials required by their backend. Operator-issued credentials SHALL be restored privately. CI SHALL NOT write secrets through the Doppler CLI.

#### Scenario: Fresh foundation
- **WHEN** foundation is rebuilt from empty state
- **THEN** both configs and scoped tokens are created and no obsolete imports are required

#### Scenario: Cluster apply
- **WHEN** a cluster root is applied
- **THEN** its backend-specific generated credentials reach its Doppler config; only prod receives Autoscaler and CSI credentials; dev receives no cloud worker credentials

#### Scenario: Autoscaler key creation
- **WHEN** prod is applied from fresh state
- **THEN** its independent autoscaler service-account key is generated and stored in that environment's Doppler config without manual creation

#### Scenario: Telemetry credential generation
- **WHEN** foundation is applied
- **THEN** both configs contain independently generated Grafana credentials unless dev retains its recovered credential

#### Scenario: Environment rebuild keeps telemetry credentials
- **WHEN** an environment is destroyed and re-provisioned
- **THEN** its telemetry credentials in Doppler are unchanged

#### Scenario: Retired component credentials
- **WHEN** a component that consumed an operator-entered secret is removed from the platform
- **THEN** its keys are deleted from the Doppler configs that held them

#### Scenario: Retired generated credentials
- **WHEN** the foundation root stops generating a telemetry credential and is applied
- **THEN** that key is deleted from the Doppler configs that held it

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

### Requirement: Credential separation
The platform SHALL keep these credentials distinct from one another:
- the HCP Terraform state token;
- CI GCP credentials, which come from GitHub OIDC;
- autoscaler GCP credentials;
- CI Doppler tokens;
- secret-store read tokens.

A credential MUST NOT be reused for another purpose. CI Doppler tokens and store tokens MUST each be scoped to one environment config. The HCP Terraform token MAY be shared by both environments, because the free tier cannot scope it to workspaces; each root MUST instead refuse to plan when its selected workspace belongs to a different environment.

#### Scenario: Backend access
- **WHEN** OpenTofu initializes a remote-state root
- **THEN** it authenticates to HCP Terraform with the HCP Terraform token only, and never with CI OIDC or autoscaler GCP credentials

#### Scenario: Workspace mismatch
- **WHEN** a cluster or platform plan runs with `env` set to one environment and the workspace of the other
- **THEN** OpenTofu fails before planning any change

#### Scenario: Autoscaler scope
- **WHEN** the production autoscaler's GCP key is used
- **THEN** it can inspect project Compute inventory and resize/remove workers through the configured production MIGs, with no object-storage access

### Requirement: Secret changes reach the cluster declaratively
When a secret value changes in Doppler, the derived Kubernetes Secret SHALL update within the store refresh interval. Workloads that read secrets only at startup SHALL use the new value after a restart triggered from Argo CD. Rotating an OpenTofu-generated credential MUST require only OpenTofu applies and, where needed, that Argo CD restart, with no kubectl or cloud CLI step. Rotating the autoscaler key MUST require only the cluster and platform applies, which restart the autoscaler with the new key.

#### Scenario: Rotate autoscaler key
- **WHEN** an operator replaces the autoscaler access key through the cluster root and the platform root is then applied
- **THEN** Doppler, the cluster Secret, and the running autoscaler all use the new key, without an Argo CD restart

#### Scenario: Update an operator-entered secret
- **WHEN** the Cloudflare tunnel token is changed in Doppler
- **THEN** the tunnel Secret updates within the refresh interval, and restarted tunnel pods use the new token

### Requirement: Secret confidentiality
Secret values MUST NOT appear in Git, routine CI logs, or OpenTofu plan output. OpenTofu state containing generated credentials SHALL be stored only in the project's HCP Terraform workspaces, whose organization membership is restricted to operators.

#### Scenario: CI log review
- **WHEN** a user reads a provisioning run's logs
- **THEN** no Doppler token, GCP key, kubeconfig, or Talos secret appears in plaintext

#### Scenario: Plan output
- **WHEN** a plan includes a generated or Doppler-sourced secret
- **THEN** the value is shown as sensitive

### Requirement: Secret store outage tolerance
If Doppler is unreachable, existing Kubernetes Secrets SHALL remain in place and workloads SHALL keep running. The failure MUST be visible on the affected ExternalSecret and store status.

#### Scenario: Doppler outage
- **WHEN** Doppler cannot be reached during a refresh
- **THEN** existing Secrets are retained unchanged, and the ExternalSecrets report a not-ready condition

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
