# doppler-secret-delivery Specification

## Purpose

Make Doppler the single source for platform secrets. OpenTofu writes generated credentials to it, and each cluster receives only its own environment's secrets through External Secrets Operator.

## Requirements

### Requirement: Doppler as the single secret source
The platform SHALL store every secret consumed by CI or clusters in the Doppler project `talos-proxmox`, in the config for the matching environment (`dev` or `prod`):
- **Generated credentials** (kubeconfig, talosconfig, autoscaler AWS access keys, and secret-store read tokens) MUST be written by OpenTofu.
- **Externally issued credentials** (Proxmox, HCP Terraform, Tailscale, Cloudflare tunnel, and Longhorn backup credentials) MUST be entered in Doppler by an operator.

No CI step MAY write secrets to Doppler with the Doppler CLI.

#### Scenario: Cluster apply
- **WHEN** the cluster root is applied
- **THEN** that environment's generated credentials are present and current in its Doppler config, with no CLI write step

#### Scenario: Autoscaler key creation
- **WHEN** an environment is applied from fresh state
- **THEN** its autoscaler access key exists and is stored in that environment's Doppler config without manual key creation

### Requirement: Clusters receive secrets only through the secret store
Every Kubernetes Secret derived from Doppler SHALL be produced by External Secrets Operator from the cluster's Doppler store, except the bootstrap authentication Secret required by that store. The platform root SHALL create and own that bootstrap Secret; ESO MUST NOT also manage it. The store's credential MUST be a read-only Doppler token scoped to that environment's config, and MUST be the only Doppler credential placed in the cluster. No provisioning step MAY create application Secrets from secret values.

#### Scenario: Bootstrap store authentication
- **WHEN** the platform root provisions a fresh environment before ESO is running
- **THEN** it creates the store's read-only token Secret from `ESO_DOPPLER_TOKEN`, and all application Secrets remain ESO-owned

#### Scenario: Application secret
- **WHEN** the Cloudflare tunnel, Longhorn backup, or autoscaler component is synced by Argo CD
- **THEN** its Secret is created by an ExternalSecret from the Doppler store, and no workflow writes that Secret directly

#### Scenario: Store token scope
- **WHEN** a store's token is used to write, or to read the other environment's config
- **THEN** Doppler rejects the request

### Requirement: Credential separation
The platform SHALL keep these credentials distinct from one another:
- the HCP Terraform state token;
- CI AWS credentials, which come from GitHub OIDC;
- autoscaler AWS credentials;
- CI Doppler tokens;
- secret-store read tokens.

A credential MUST NOT be reused for another purpose. CI Doppler tokens and store tokens MUST each be scoped to one environment config. The HCP Terraform token MAY be shared by both environments, because the free tier cannot scope it to workspaces; each root MUST instead refuse to plan when its selected workspace belongs to a different environment.

#### Scenario: Backend access
- **WHEN** OpenTofu initializes a remote-state root
- **THEN** it authenticates to HCP Terraform with the HCP Terraform token only, and never with CI OIDC or autoscaler AWS credentials

#### Scenario: Workspace mismatch
- **WHEN** a cluster or platform plan runs with `env` set to one environment and the workspace of the other
- **THEN** OpenTofu fails before planning any change

#### Scenario: Autoscaler scope
- **WHEN** the autoscaler's AWS key is used
- **THEN** it can scale only its own environment's burst group

### Requirement: Secret changes reach the cluster declaratively
When a secret value changes in Doppler, the derived Kubernetes Secret SHALL update within the store refresh interval. Workloads that read secrets only at startup SHALL use the new value after a restart triggered from Argo CD. Rotating an OpenTofu-generated credential MUST require only an OpenTofu apply and, where needed, that Argo CD restart, with no kubectl or cloud CLI step.

#### Scenario: Rotate autoscaler key
- **WHEN** an operator replaces the autoscaler access key through OpenTofu and restarts the autoscaler from Argo CD after the Secret refreshes
- **THEN** Doppler, the cluster Secret, and the running autoscaler all use the new key

#### Scenario: Update an operator-entered secret
- **WHEN** the Cloudflare tunnel token is changed in Doppler
- **THEN** the tunnel Secret updates within the refresh interval, and restarted tunnel pods use the new token

### Requirement: Secret confidentiality
Secret values MUST NOT appear in Git, routine CI logs, or OpenTofu plan output. OpenTofu state containing generated credentials SHALL be stored only in the project's HCP Terraform workspaces, whose organization membership is restricted to operators.

#### Scenario: CI log review
- **WHEN** a user reads a provisioning run's logs
- **THEN** no Doppler token, AWS key, kubeconfig, or Talos secret appears in plaintext

#### Scenario: Plan output
- **WHEN** a plan includes a generated or Doppler-sourced secret
- **THEN** the value is shown as sensitive

### Requirement: Secret store outage tolerance
If Doppler is unreachable, existing Kubernetes Secrets SHALL remain in place and workloads SHALL keep running. The failure MUST be visible on the affected ExternalSecret and store status.

#### Scenario: Doppler outage
- **WHEN** Doppler cannot be reached during a refresh
- **THEN** existing Secrets are retained unchanged, and the ExternalSecrets report a not-ready condition
