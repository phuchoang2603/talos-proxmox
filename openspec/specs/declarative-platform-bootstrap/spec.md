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
The platform SHALL consist only of the `dev` and `prod` environments. Each MUST run its own Argo CD, which manages only its own cluster. An environment MUST NOT hold credentials for, depend on, or be ordered after another environment or a separate management cluster.

#### Scenario: Provision one environment alone
- **WHEN** only prod is provisioned from fresh state
- **THEN** prod reaches a fully synced platform without dev existing

#### Scenario: Lose one environment
- **WHEN** the dev cluster is destroyed
- **THEN** prod's Argo CD, applications, and secrets are unaffected

#### Scenario: Cross-environment access
- **WHEN** a cluster's Argo CD or secret store is inspected
- **THEN** it holds no credentials for the other environment

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

### Requirement: Cluster health gate
The platform root SHALL gate Argo CD installation on fixed-node health after the CNI is installed. When no Kubernetes node labeled `burst.talos.dev/compute=aws` is registered, it SHALL run `talos_cluster_health` using the fixed inventory's control-plane and worker addresses, with a 15-minute timeout for Talos, etcd, and Kubernetes health checks. When any node with that label is registered, it SHALL instead require every fixed inventory node name to be registered and Kubernetes Ready, and SHALL skip the Talos and etcd checks. A failed gate MUST fail the platform apply. Autoscaled AWS workers MUST NOT be required to exist or be Ready for the health gate to pass.

#### Scenario: Initial provision without burst workers
- **WHEN** a fresh environment has only its fixed inventory nodes and no AWS burst workers
- **THEN** the gate runs the Talos, etcd, and Kubernetes checks against the fixed inventory without launching or waiting for any burst worker

#### Scenario: Healthy cluster
- **WHEN** no burst node is registered and all fixed control-plane and worker nodes pass the Talos, etcd, and Kubernetes checks after CNI installation
- **THEN** the health gate passes and permits Argo CD installation

#### Scenario: Unhealthy fixed node
- **WHEN** no burst node is registered and the fixed-node health checks do not pass within the 15-minute timeout
- **THEN** the platform apply fails visibly, and CI reports the environment as not provisioned

#### Scenario: Registered burst node
- **WHEN** any AWS burst node is registered and every fixed inventory node is registered and Kubernetes Ready after CNI installation
- **THEN** the health gate passes without checking burst-node readiness or running Talos and etcd checks

#### Scenario: Missing or unready fixed node with burst workers
- **WHEN** an AWS burst node is registered and a fixed inventory node is missing or is not Kubernetes Ready
- **THEN** the fixed-node readiness postcondition fails the platform apply

#### Scenario: Terminated burst node
- **WHEN** a terminated AWS burst node is still registered as NotReady and every fixed inventory node is registered and Kubernetes Ready
- **THEN** the gate passes using fixed-node Kubernetes readiness only, without running Talos and etcd checks

### Requirement: Per-cluster GitOps enablement
Each environment's Argo CD SHALL reconcile its components from one shared Git platform definition. Each component MUST declare which environments it runs on and MAY vary values per environment. Storage, GPU, burst, and ingress components MUST be enabled only on environments that have the corresponding nodes or needs.

#### Scenario: Storage selection
- **WHEN** the platform definition is reconciled
- **THEN** prod runs Longhorn, dev runs local-path, and neither cluster has more than one default StorageClass

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
