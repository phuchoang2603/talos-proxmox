## MODIFIED Requirements

### Requirement: Self-contained environments
Each environment SHALL use an independent Talos identity, credentials, namespaces, object storage and application domains. Inactive provider configuration MUST NOT require credentials for the other backend. Dev SHALL use Proxmox and existing MinIO; prod SHALL use AWS and S3.

#### Scenario: Prod bootstrap
- **WHEN** prod is applied without Proxmox or MinIO credentials
- **THEN** it provisions without reading dev configuration

#### Scenario: Provision one environment alone
- **WHEN** only prod is provisioned after an explicitly selected promotion
- **THEN** its runtime reaches convergence without depending on a running dev cluster

#### Scenario: Provision dev without prod
- **WHEN** dev is provisioned while prod does not exist or is unreachable
- **THEN** dev reaches a fully synced platform with no failing component

#### Scenario: Lose one environment
- **WHEN** the dev cluster is destroyed
- **THEN** prod's Argo CD, applications, and secrets are unaffected

#### Scenario: Cross-environment access
- **WHEN** a cluster's Argo CD or secret store is inspected
- **THEN** it holds no credentials for the other environment

### Requirement: Per-cluster GitOps enablement
Both environments SHALL reconcile the same applicable platform services with environment values for storage, domains, credentials and lean activity. Provider/hardware components SHALL follow capabilities. Dev SHALL use local-path and prod gp3, with only one default class per cluster. Knative Serving, Eventing and Istio networking SHALL be enabled before Kubeflow in both environments.

#### Scenario: Serverless inference
- **WHEN** a KServe service is submitted in either environment
- **THEN** Knative serves a request and idle inference can scale to zero

#### Scenario: Storage selection
- **WHEN** the shared platform reconciles
- **THEN** dev runs local-path and prod runs gp3 EBS CSI, each with exactly one default StorageClass and no Longhorn

#### Scenario: Component disabled for an environment
- **WHEN** a component does not list an environment
- **THEN** that environment's Argo CD has no Application for it

### Requirement: Layered roots in CI
PR validation SHALL lint roots and charts without state or secrets; a separate trusted repository PR job SHALL deploy dev. Main SHALL deploy dev, then prod only after dev succeeds. Fork PRs SHALL validate without deployment secrets. Foundation SHALL be applied by the operator. Root and child Argo applications SHALL share the selected revision.

#### Scenario: Unpromoted commit
- **WHEN** a commit reaches main
- **THEN** prod receives that pinned commit only after the dev deployment succeeds

#### Scenario: Pull request
- **WHEN** a pull request targets `main`
- **THEN** the foundation, cluster, and platform roots and the platform charts, including dev overlays, are linted without state or deployment secrets

#### Scenario: Push to main
- **WHEN** a validated change reaches main
- **THEN** an existing dev environment receives the selected revision, followed by prod only after dev succeeds; absent dev requires manual recreation

#### Scenario: Dev on demand
- **WHEN** dev has been intentionally destroyed
- **THEN** automatic deployment does not recreate it; an explicit manual apply can recreate it

#### Scenario: Foundation change
- **WHEN** a foundation root file changes
- **THEN** CI only lints it, and an operator applies it locally

### Requirement: Cluster-only environment teardown
Environment teardown SHALL clean owned external worker and CSI resources through AWS APIs independently of Kubernetes. Normal teardown SHALL retain declared persistent data; explicit purge SHALL delete it. Only successful cluster cleanup SHALL permit platform state reset. Foundation SHALL remain separately owned.

#### Scenario: Cleanup fails
- **WHEN** external cleanup returns an error
- **THEN** platform state remains intact and the failure is reported

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

### Requirement: Single declarative owner per component
Each infrastructure resource, cluster component, and secret SHALL have exactly one declarative owner:
- the foundation root owns account, identity, and secret-store setup;
- the cluster root owns machines and generated credentials;
- the platform root owns Gateway API CRDs, Cilium, Talos CCM, secret-store bootstrap credentials, Karpenter in prod and Argo CD with its AppProject and root Application;
- the environment's Argo CD owns Istio, the Cloudflare operator/CRDs/ClusterTunnel, Argo CD OAuth/tunnel access and other applications.

No component MAY be managed by both OpenTofu and Argo CD. No UI Gateway or HTTPRoute SHALL be rendered by the bootstrap chart.

Gateway API CRDs SHALL be installed from a pinned Helm chart archive committed to Git. Cilium SHALL use `kube-system` for its namespaced resources. Charts and releases SHALL handle any additional namespace they require declaratively; provisioning MUST NOT create per-component namespaces through scripts. Cluster-scoped Cilium resources remain cluster-scoped.

#### Scenario: Pre-GitOps components
- **WHEN** the platform root is applied to an environment
- **THEN** it installs Gateway API CRDs, Cilium, Talos CCM, the bootstrap token Secret, Karpenter in prod and Argo CD with its root Application, without UI LoadBalancer Services or a bootstrap dependency on ESO/Cloudflare CRDs

#### Scenario: Drift on an Argo-owned component
- **WHEN** an Argo-owned component is changed in Git
- **THEN** only Argo CD reconciles it, and the next OpenTofu plan shows no change for it

#### Scenario: UI publishing
- **WHEN** the environment tunnel routes reconcile
- **THEN** Argo CD and Grafana use their environment hostnames backed by ClusterIP Services, with management port-forward available
