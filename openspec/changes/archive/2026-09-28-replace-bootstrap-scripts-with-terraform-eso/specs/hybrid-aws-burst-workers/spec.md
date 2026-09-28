## MODIFIED Requirements

### Requirement: Secure, Git-managed reconciliation
The platform SHALL manage Proxmox and AWS infrastructure in one root with a separate HCP Terraform state workspace per cluster environment, and reconcile in-cluster autoscaling, storage drivers, and storage policies from Git. It MUST protect Talos identities and bootstrap material and cloud credentials from repository disclosure, use different credentials for HCP Terraform state, AWS provisioning, and on-premises autoscaling, and prevent infrastructure reconciliation from overwriting the autoscaler's desired worker count.

#### Scenario: Reconcile the AWS infrastructure
- **WHEN** Git-managed infrastructure changes are applied while the autoscaler owns worker capacity
- **THEN** worker count remains within declared bounds without an unrelated reset of the autoscaler's chosen desired capacity

#### Scenario: Inspect repository and pipeline logs
- **WHEN** a user reads committed configurations or routine CI output
- **THEN** Talos cluster secrets, AWS credentials, and machine bootstrap configurations are not exposed in plaintext

#### Scenario: Distinct AWS access from CI and autoscaler
- **WHEN** CI plans/provisions AWS infrastructure and the on-premises autoscaler adjusts its AWS worker group
- **THEN** neither process authenticates to AWS with the HCP Terraform token, and the autoscaler cannot use the broader CI provisioning credential

### Requirement: Lint PRs and provision from main only
The platform SHALL lint all OpenTofu roots and platform charts on pull requests targeting `main` without exposing state, AWS credentials, or Doppler environment secrets. Only a push or explicitly dispatched workflow on `main` SHALL plan and apply changes. AWS access in CI MUST use a scoped GitHub OIDC role, separate from the HCP Terraform token; the on-premises autoscaler SHALL have separate scaling-only credentials before it is enabled.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the OpenTofu roots and platform charts are linted without accessing remote state or deployment secrets

#### Scenario: Push to main
- **WHEN** reviewed changes are pushed to `main`
- **THEN** dev and prod generate fresh plans and apply through their main-only deployment environments

#### Scenario: Manual run from another branch
- **WHEN** a manual workflow dispatch targets a ref other than `main`
- **THEN** no infrastructure apply or destroy job runs
