# declarative-platform-bootstrap Specification

## Purpose

Bring the dev and prod Talos environments from fresh state to a fully reconciled platform using only declarative OpenTofu roots and an in-cluster Argo CD, with exactly one owner for each infrastructure resource and cluster component.

## Requirements

### Requirement: Script-free environment bring-up
The platform SHALL provision an environment from empty state to an eventually fully synced platform using only Git content, OpenTofu applies, and Argo CD reconciliation. Provisioning MUST NOT run repository bootstrap scripts, and MUST NOT create Kubernetes resources with the helm or kubectl CLIs. CI success SHALL mean the cluster and platform applies completed; full GitOps convergence SHALL be validated separately after provisioning.

#### Scenario: Fresh environment
- **WHEN** CI applies an environment's cluster and platform roots against empty state
- **THEN** the cluster becomes healthy and its Argo CD converges all of the environment's enabled components without any script or manual kubectl/helm step

#### Scenario: Provisioning completes before GitOps convergence
- **WHEN** the cluster and platform applies succeed and the root Application is installed
- **THEN** provisioning CI succeeds without waiting for all child Applications or SPIRE to become healthy, and full platform validation occurs later

#### Scenario: Repeat apply
- **WHEN** CI re-applies an unchanged environment
- **THEN** OpenTofu reports no changes to cluster components or secrets, and Argo CD applications stay Synced

### Requirement: Self-contained environments
The platform SHALL consist only of the `dev` and `prod` environments. Each MUST run its own Argo CD, which manages only its own cluster. An environment MUST NOT hold credentials for, depend on, or be ordered after another environment or a separate management cluster, with one exception: dev MAY hold the write-only telemetry ingest credential for prod's ingest endpoint. That credential MUST NOT grant read access to prod telemetry or any other access to prod, and dev MUST converge whether or not prod is reachable.

#### Scenario: Provision one environment alone
- **WHEN** only prod is provisioned from fresh state
- **THEN** prod reaches a fully synced platform without dev existing

#### Scenario: Provision dev without prod
- **WHEN** dev is provisioned while prod does not exist or is unreachable
- **THEN** dev reaches a fully synced platform, and only its telemetry export fails

#### Scenario: Lose one environment
- **WHEN** the dev cluster is destroyed
- **THEN** prod's Argo CD, applications, and secrets are unaffected

#### Scenario: Cross-environment access
- **WHEN** a cluster's Argo CD or secret store is inspected
- **THEN** it holds no credentials for the other environment, except dev's write-only telemetry ingest credential for prod

### Requirement: Single declarative owner per component
Each infrastructure resource, cluster component, and secret SHALL have exactly one declarative owner:
- the foundation root owns account, identity, and secret-store setup;
- the cluster root owns machines and generated credentials;
- the platform root owns only the components required before GitOps can run;
- the environment's Argo CD owns everything else.

The platform root MUST be limited to Gateway API CRDs, the CNI, the secret-store bootstrap token Secret, and Argo CD with its root Application and UI route. No component MAY be managed by both OpenTofu and Argo CD.

Gateway API CRDs SHALL be installed from a pinned Helm chart archive committed to Git. Cilium and SPIRE SHALL share `kube-system` for their namespaced resources. Their chart/release SHALL handle any additional namespace it requires declaratively; provisioning MUST NOT create per-component namespaces through scripts. Cluster-scoped Cilium resources remain cluster-scoped.

#### Scenario: Pre-GitOps components
- **WHEN** the platform root is applied to an environment
- **THEN** it installs only Gateway API CRDs, the CNI, the bootstrap token Secret, and Argo CD with its root Application and UI route

#### Scenario: Drift on an Argo-owned component
- **WHEN** an Argo-owned component is changed in Git
- **THEN** only Argo CD reconciles it, and the next OpenTofu plan shows no change for it

### Requirement: Platform API readiness and installation ordering
The platform root SHALL wait for the Kubernetes API's authenticated `/readyz` endpoint to return HTTP 200 before creating Kubernetes resources or installing Helm releases. It SHALL install Gateway API CRDs before Cilium, and Cilium before Argo CD. It MUST NOT gate provisioning on Talos, etcd, or Kubernetes node health checks or require a fixed-node inventory or Talos client configuration. Helm release readiness checks MAY still fail installation when the release's own resources cannot become ready. Successful provisioning SHALL confirm platform resource installation; node health and full GitOps convergence SHALL be checked separately during operations.

#### Scenario: API is starting
- **WHEN** the Kubernetes API is not yet ready after cluster provisioning
- **THEN** the platform retries the authenticated readiness request before installing resources, and fails if readiness is not reached within the configured retry budget

#### Scenario: Install Argo CD
- **WHEN** the API is ready and the Gateway API and Cilium releases have been installed
- **THEN** Argo CD installation proceeds without a separate node health check

#### Scenario: Unready node
- **WHEN** a fixed or burst node is NotReady but the API and the platform release resources can become ready
- **THEN** that node's status does not independently fail the platform apply

#### Scenario: Argo CD cannot become ready
- **WHEN** Argo CD's release resources cannot become ready within the Helm timeout
- **THEN** the platform apply fails through the release readiness check

### Requirement: Per-cluster GitOps enablement
Each environment's Argo CD SHALL reconcile its components from one shared Git platform definition. Each component MUST declare which environments it runs on and MAY vary values per environment. Storage, GPU, burst, and ingress components MUST be enabled only on environments that have the corresponding nodes or needs.

#### Scenario: Storage selection
- **WHEN** the platform definition is reconciled
- **THEN** both dev and prod run local-path, neither runs Longhorn, and neither cluster has more than one default StorageClass

#### Scenario: Component disabled for an environment
- **WHEN** a component does not list an environment
- **THEN** that environment's Argo CD has no Application for it

### Requirement: Layered roots in CI
PR checks SHALL lint all OpenTofu roots and platform charts without accessing state or secrets. Static validation logic SHALL live directly in `.github/workflows/lint.yml`, without a separate repository validation script or duplicate devenv chart-validation hook. Only `main` pushes or explicitly dispatched `main` runs SHALL apply the cluster and platform roots, for dev and prod independently. The foundation root MUST NOT be applied by CI.

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the foundation, cluster, and platform roots and the platform charts are linted without state or deployment secrets

#### Scenario: Push to main
- **WHEN** changes are pushed to `main`
- **THEN** dev and prod each apply their cluster root, then their platform root, in parallel, with no repository scripts

#### Scenario: Foundation change
- **WHEN** a foundation root file changes
- **THEN** CI only lints it, and an operator applies it locally

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
