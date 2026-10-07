## MODIFIED Requirements

### Requirement: Doppler as the single secret source
The platform SHALL store every secret consumed by CI or clusters in the Doppler project `talos-proxmox`, in the config for the matching environment (`dev` or `prod`):
- **Generated credentials** (kubeconfig, talosconfig, autoscaler AWS access keys, AWS worker bootstrap configuration, secret-store read tokens, telemetry store credentials, and the telemetry UI admin credential) MUST be written by OpenTofu. The foundation root SHALL generate the telemetry store credentials and the telemetry UI admin credential into the `prod` config only.
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
- **THEN** the `prod` config holds the telemetry store credentials and the telemetry UI admin credential, the `dev` config holds no telemetry credential, and no operator typed any of those values

#### Scenario: Environment rebuild keeps telemetry credentials
- **WHEN** an environment is destroyed and re-provisioned
- **THEN** its telemetry credentials in Doppler are unchanged

#### Scenario: Retired component credentials
- **WHEN** a component that consumed an operator-entered secret is removed from the platform
- **THEN** its keys are deleted from the Doppler configs that held them

#### Scenario: Retired generated credentials
- **WHEN** the foundation root stops generating a telemetry credential and is applied
- **THEN** that key is deleted from the Doppler configs that held it
