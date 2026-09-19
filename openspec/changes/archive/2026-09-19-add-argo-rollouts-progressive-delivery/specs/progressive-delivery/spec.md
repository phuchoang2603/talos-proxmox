## Purpose

Provide declarative progressive delivery on the dev and prod workload clusters while retaining centralized GitOps ownership in the Argo CD management cluster.

## ADDED Requirements

### Requirement: Cluster-local rollout reconciliation
The platform SHALL run an Argo Rollouts controller and install the required custom resource definitions in every workload cluster where Rollout resources are supported. The platform MUST NOT rely on a controller in the `argocd` management cluster to reconcile Rollout resources in remote clusters.

#### Scenario: Dev controller placement
- **WHEN** the dev platform root is synchronized
- **THEN** the Argo Rollouts custom resource definitions and controller are available in the dev cluster
- **THEN** no Argo Rollouts controller is required in the `argocd` cluster

#### Scenario: Prod controller placement
- **WHEN** the prod platform root is synchronized
- **THEN** the Argo Rollouts custom resource definitions and controller are available in the prod cluster
- **THEN** the prod controller reconciles only resources visible through the prod Kubernetes API

### Requirement: Central GitOps ownership
The platform SHALL let the central Argo CD installation deploy and continuously reconcile the Argo Rollouts platform component in both registered workload clusters using the existing platform app-of-apps model.

#### Scenario: Reconcile controller configuration
- **WHEN** the desired Argo Rollouts component configuration changes in Git
- **THEN** Argo CD synchronizes that configuration to both dev and prod according to their platform roots

#### Scenario: Correct destination cluster
- **WHEN** Argo CD renders a workload-cluster platform root
- **THEN** the generated Argo Rollouts Application targets the named workload cluster rather than the management cluster

### Requirement: Progressive workload strategies
The installed capability SHALL support Kubernetes workloads expressed as Rollout resources using blue-green or canary strategies without requiring all existing Deployments to migrate at once.

#### Scenario: Blue-green workload
- **WHEN** an application team synchronizes a valid blue-green Rollout and its referenced Services after the controller is healthy
- **THEN** the workload cluster controller manages preview and active revisions according to the declared strategy

#### Scenario: Canary workload
- **WHEN** an application team synchronizes a valid canary Rollout after the controller is healthy
- **THEN** the workload cluster controller advances, pauses, aborts, or rolls back the revision according to the declared canary steps

#### Scenario: Existing Deployment remains supported
- **WHEN** an application continues to use a standard Kubernetes Deployment
- **THEN** installing Argo Rollouts does not require that application to be converted to a Rollout

### Requirement: Cilium Gateway API canary traffic routing
The platform SHALL install and register a pinned Argo Rollouts Gateway API traffic-router plugin in every supported workload cluster. A canary Rollout SHALL be able to use the plugin to translate each declared `setWeight` step into complementary stable and canary backend weights on an application-owned HTTPRoute enforced by Cilium.

#### Scenario: Apply a canary traffic weight
- **WHEN** a Rollout declares `setWeight: 20` and references an HTTPRoute rule containing both its stable and canary Services
- **THEN** the plugin updates that rule to weight the stable backend at 80 and the canary backend at 20
- **THEN** Cilium routes application requests according to those backend weights

#### Scenario: Preserve unrelated route rules
- **WHEN** an HTTPRoute contains a rule that does not reference both the Rollout's stable and canary Services
- **THEN** the plugin leaves that rule unchanged

#### Scenario: Reject an invalid traffic-routing contract
- **WHEN** a canary Rollout references an HTTPRoute with no rule containing both its stable and canary Services
- **THEN** the traffic-routing step fails visibly rather than silently advancing the Rollout

#### Scenario: Return traffic to the stable revision
- **WHEN** a routed canary is aborted or completes promotion
- **THEN** the controller and plugin return application traffic to the resulting stable revision according to the Rollout lifecycle

### Requirement: Gateway API plugin permissions
The platform SHALL grant the Rollouts controller only the additional Kubernetes permissions needed to read referenced Services and read or update supported application route resources across workload namespaces. The plugin MUST NOT require permission to mutate Gateways or GatewayClasses.

#### Scenario: Update an application HTTPRoute
- **WHEN** a valid Rollout changes its canary weight
- **THEN** the controller service account can read the referenced Services and patch the matching HTTPRoute

#### Scenario: Gateway ownership remains separate
- **WHEN** the plugin manages canary traffic weights
- **THEN** the application's Gateway attachment and the cluster's GatewayClass remain unchanged

### Requirement: Metric-assisted analysis
The capability SHALL allow namespaced and cluster-scoped analysis templates to evaluate rollout health using the workload cluster's Prometheus-compatible VictoriaMetrics query endpoint.

#### Scenario: Successful analysis
- **WHEN** a Rollout invokes a valid analysis template and its success condition is satisfied by VictoriaMetrics query results
- **THEN** the controller permits the Rollout to continue according to its strategy

#### Scenario: Failed analysis
- **WHEN** an analysis reaches its declared failure limit or produces a result matching its failure condition
- **THEN** the controller marks the analysis failed and applies the Rollout's declared failure behavior without changing Git

### Requirement: Reproducible and verifiable installation
The Argo Rollouts dependency and Gateway API plugin image SHALL be pinned consistently with the repository's dependency conventions, and repository validation SHALL render the component for every supported workload environment without requiring cluster access.

#### Scenario: Offline validation succeeds
- **WHEN** repository validation runs with a valid Argo Rollouts component configuration
- **THEN** it lints the wrapper chart and renders the dev and prod platform configurations successfully

#### Scenario: Invalid component configuration
- **WHEN** the chart or platform configuration cannot render for a supported workload environment
- **THEN** repository validation fails before the change is applied to a cluster

### Requirement: Rollout operations are documented
The repository SHALL document how operators verify controller readiness and inspect, promote, abort, restart, and observe Rollout resources using explicit workload-cluster credentials.

#### Scenario: Operator selects a workload cluster
- **WHEN** an operator follows a documented Rollout command for dev or prod
- **THEN** the command explicitly selects the corresponding workload-cluster kubeconfig and does not depend on the default kubeconfig

#### Scenario: Failed rollout investigation
- **WHEN** a Rollout is paused, degraded, or aborted
- **THEN** the documentation provides commands to inspect the Rollout, its analysis runs, and its related pods and events
