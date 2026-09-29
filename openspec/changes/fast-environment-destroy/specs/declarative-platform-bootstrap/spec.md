## ADDED Requirements

### Requirement: Cluster-only environment teardown
Destroying an environment through the provisioning workflow SHALL destroy the cluster root and then remove every resource from the platform root's state, without destroying the platform root's resources individually. The destroy MUST NOT require the environment's Kubernetes API to be reachable. The platform root's state SHALL be reset only after the cluster root destroy succeeds. The platform root and the components the environment's Argo CD installs MUST NOT create resources outside the cluster that need removal when the environment is destroyed, except the autoscaler's AWS instances and launch templates, which the cluster root removes. After a destroy, the next apply SHALL provision the environment as it would from empty state.

#### Scenario: Destroy a healthy environment
- **WHEN** an operator runs the destroy workflow for an environment
- **THEN** the cluster root is destroyed, the platform root's state is empty, and no in-cluster component is uninstalled individually beforehand

#### Scenario: Destroy an environment with an unreachable API
- **WHEN** the environment's Kubernetes API is down or unreachable from CI and an operator runs the destroy workflow
- **THEN** the destroy completes and the platform root's state is empty

#### Scenario: Cluster destroy fails
- **WHEN** the cluster root destroy fails
- **THEN** the platform root's state is left unchanged, and re-running the destroy retries the cluster root before resetting the platform state

#### Scenario: Re-provision after destroy
- **WHEN** CI applies an environment after a destroy
- **THEN** the cluster root and then the platform root are applied as they would be from empty state, and the platform apply does not fail because of resources recorded before the destroy

#### Scenario: Component with external side effects
- **WHEN** a component added to the platform root or Argo CD would create a resource outside the cluster that must be removed on destroy
- **THEN** that resource's removal is owned by the cluster or foundation root, not by the component's in-cluster teardown
