## MODIFIED Requirements

### Requirement: Layered roots in CI
PR checks SHALL lint all OpenTofu roots and platform charts without accessing state or secrets. Static validation logic SHALL live directly in `.github/workflows/lint.yml`, without a separate repository validation script or duplicate devenv chart-validation hook. Pushes to `main` SHALL apply the cluster and platform roots for prod only. Dev SHALL be applied or destroyed only by an explicitly dispatched `main` run; no push MAY create, update, or destroy dev. The foundation root MUST NOT be applied by CI.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the foundation, cluster, and platform roots and the platform charts, including dev overlays, are linted without state or deployment secrets

#### Scenario: Push to main
- **WHEN** changes are pushed to `main`
- **THEN** prod applies its cluster root, then its platform root, with no repository scripts, and no dev job runs

#### Scenario: Dev on demand
- **WHEN** an operator dispatches the manual provisioning workflow on `main` for dev with `apply` or `destroy`
- **THEN** dev is built from the current `main` or torn down, and prod is unaffected

#### Scenario: Foundation change
- **WHEN** a foundation root file changes
- **THEN** CI only lints it, and an operator applies it locally
