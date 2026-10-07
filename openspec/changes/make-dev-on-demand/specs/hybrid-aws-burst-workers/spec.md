## MODIFIED Requirements

### Requirement: Lint PRs and provision from main only
The platform SHALL lint all OpenTofu roots and platform charts on pull requests targeting `main` without exposing state, AWS credentials, or Doppler environment secrets. Only a push or explicitly dispatched workflow on `main` SHALL plan and apply changes. AWS access in CI MUST use a scoped GitHub OIDC role, separate from the HCP Terraform token; CI MUST NOT be able to launch AWS worker instances itself. CI MAY terminate autoscaled AWS worker instances and delete their launch templates, limited to resources tagged as autoscaled by this platform, so that a destroy can remove them. The on-premises autoscaler SHALL have separate credentials, limited to managing its environment's workers, before it is enabled.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the OpenTofu roots and platform charts are linted without accessing remote state or deployment secrets

#### Scenario: Push to main
- **WHEN** reviewed changes are pushed to `main`
- **THEN** prod generates a fresh plan and applies through its main-only deployment environment, and dev is applied only when an operator dispatches it

#### Scenario: Manual run from another branch
- **WHEN** a manual workflow dispatch targets a ref other than `main`
- **THEN** no infrastructure apply or destroy job runs

#### Scenario: CI credential used to launch or terminate other instances
- **WHEN** the CI provisioning role attempts to launch an EC2 instance, or to terminate an instance that is not tagged as an autoscaled worker of this platform
- **THEN** AWS denies the request
