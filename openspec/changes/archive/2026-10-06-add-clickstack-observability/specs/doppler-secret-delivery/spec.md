## MODIFIED Requirements

### Requirement: Doppler as the single secret source
The platform SHALL store every secret consumed by CI or clusters in the Doppler project `talos-proxmox`, in the config for the matching environment (`dev` or `prod`):
- **Generated credentials** (kubeconfig, talosconfig, autoscaler AWS access keys, AWS worker bootstrap configuration, secret-store read tokens, telemetry store credentials, and the telemetry ingest token) MUST be written by OpenTofu. The foundation root SHALL generate the telemetry store credentials into the `prod` config only, and one telemetry ingest token into both configs.
- **Externally issued credentials** (Proxmox, HCP Terraform, Tailscale, and Cloudflare tunnel credentials) MUST be entered in Doppler by an operator.

No CI step MAY write secrets to Doppler with the Doppler CLI. A Doppler config MUST NOT keep keys that no CI step or cluster component consumes.

#### Scenario: Cluster apply
- **WHEN** the cluster root is applied
- **THEN** that environment's generated credentials and AWS worker bootstrap configuration are present and current in its Doppler config, with no CLI write step

#### Scenario: Autoscaler key creation
- **WHEN** an environment is applied from fresh state
- **THEN** its autoscaler access key exists and is stored in that environment's Doppler config without manual key creation

#### Scenario: Telemetry credential generation
- **WHEN** an operator applies the foundation root
- **THEN** the `prod` config holds the telemetry store credentials, both configs hold the same telemetry ingest token, and no operator typed any of those values

#### Scenario: Environment rebuild keeps telemetry credentials
- **WHEN** an environment is destroyed and re-provisioned
- **THEN** its telemetry credentials in Doppler are unchanged

#### Scenario: Retired component credentials
- **WHEN** a component that consumed an operator-entered secret is removed from the platform
- **THEN** its keys are deleted from the Doppler configs that held them

### Requirement: Clusters receive secrets only through the secret store
Every Kubernetes Secret derived from Doppler SHALL be produced by External Secrets Operator from the cluster's Doppler store, except the bootstrap authentication Secret required by that store and the autoscaler's AWS credential Secret. The platform root SHALL create and own those two Secrets; ESO MUST NOT also manage them. The store's credential MUST be a read-only Doppler token scoped to that environment's config, and MUST be the only Doppler credential placed in the cluster. No provisioning step MAY create other application Secrets from secret values.

#### Scenario: Bootstrap store authentication
- **WHEN** the platform root provisions a fresh environment before ESO is running
- **THEN** it creates the store's read-only token Secret from `ESO_DOPPLER_TOKEN`, and all application Secrets other than the autoscaler credential remain ESO-owned

#### Scenario: Autoscaler credential
- **WHEN** the platform root installs the autoscaler
- **THEN** it creates the autoscaler's AWS credential Secret from the environment's Doppler config, and no ExternalSecret manages that Secret

#### Scenario: Application secret
- **WHEN** the Cloudflare tunnel, observability, or telemetry agent component is synced by Argo CD
- **THEN** its Secrets are created by ExternalSecrets from the Doppler store, and no workflow writes those Secrets directly

#### Scenario: Store token scope
- **WHEN** a store's token is used to write, or to read the other environment's config
- **THEN** Doppler rejects the request
