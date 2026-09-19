## Context

Argo CD runs in the `argocd` cluster and already creates child Applications whose destinations are the registered `dev` and `prod` clusters. The platform chart is the repository's control point for workload-cluster operators. Argo Rollouts is an in-cluster Kubernetes controller: it cannot use Argo CD's remote-cluster credentials or reconcile Rollout resources across cluster boundaries.

Components in this repository are wrapper charts with pinned upstream dependencies, committed lock files and chart archives, shared defaults, and optional per-environment values. The dev cluster is a single-node environment; prod has multiple nodes. Both clusters run Cilium with Envoy and Gateway API enabled, and existing Gateway and HTTPRoute resources confirm that Cilium is already the north-south routing implementation. Both clusters also run the same VictoriaMetrics observability stack and expose its Prometheus-compatible query API through `vmsingle-vmks.monitoring.svc.cluster.local:8428`.

## Goals / Non-Goals

**Goals:**

- Make the controller installation repeatable through the existing app-of-apps path.
- Keep rollout execution and failure isolation inside each workload cluster.
- Provide sensible resource and replica defaults for the differently sized dev and prod clusters.
- Preserve CRDs during component removal so an uninstall cannot implicitly delete adopted Rollout resources.
- Provide precise Cilium-enforced HTTP canary weights through the Argo Rollouts Gateway API plugin.
- Establish a documented pattern for optional VictoriaMetrics analysis.

**Non-Goals:**

- Converting an existing application Deployment to a Rollout.
- Installing a Rollouts controller or dashboard in the management cluster.
- Providing cross-cluster rollout coordination.
- Exposing the Rollouts dashboard through Gateway API or Cloudflare Tunnel.
- Creating application-specific Gateways, HTTPRoutes, Services, rollout steps, or analysis thresholds.
- Supporting GRPCRoute, TCPRoute, TLSRoute, header-based experiments, or Gateway API implementations other than the existing Cilium installation in the first iteration.

## Decisions

### Use one cluster-scoped installation per workload cluster

Add `apps/components/argo-rollouts` as a wrapper around the upstream `argo-rollouts` Helm chart and generate one Argo CD Application for it in each platform root. The release targets an `argo-rollouts` namespace in the selected remote cluster with cluster-scoped RBAC, allowing workloads in any application namespace to adopt Rollouts.

This follows the controller's supported architecture and the repository's existing multi-cluster model. A controller in the management cluster was rejected because Argo Rollouts does not reconcile external clusters. Namespace-scoped controllers were rejected because they would multiply installations and prevent a single platform service from supporting all application namespaces.

### Let the chart manage CRDs, but retain them on uninstall

Set the upstream chart to install and upgrade CRDs and retain them when the Helm release is removed. Argo CD continues to use server-side apply for the component Application. Removing the component Application must be treated as a staged operation: stop creating Rollouts, migrate or delete remaining custom resources, remove the controller, and only then explicitly remove CRDs if desired.

Chart-managed CRDs were selected over a separate bootstrap component so controller and API versions stay pinned together. Automatic CRD deletion was rejected because deleting a CRD also deletes all corresponding custom resources and would be unsafe after application adoption.

### Size controller replicas by environment

Use shared conservative CPU and memory requests/limits, one controller replica in dev, and two replicas in prod. The prod pair uses leader election supplied by the upstream chart and anti-affinity/topology spreading where schedulable. Keep the dashboard disabled; operators use Argo CD resource actions, the kubectl plugin, and Kubernetes resource inspection instead.

Running two replicas everywhere was rejected because it provides no node-level availability on the single-node dev cluster. A single prod replica was rejected because controller unavailability would stall active promotions and analysis even though running workloads would continue serving.

### Install the Gateway API traffic-router plugin from a pinned image

Configure each Rollouts controller with the `argoproj-labs/gatewayAPI` traffic-router plugin. A pinned plugin container image, preferably locked by immutable digest, runs as an init container and copies the plugin binary into a shared `emptyDir`; the controller registers the resulting local `file://` path. This avoids downloading an executable from GitHub at controller startup and makes the deployed artifact auditable and repeatable.

The wrapper chart also creates a cluster-scoped role and binding for the controller service account. Additional permissions are limited to reading Services and getting, listing, updating, and patching HTTPRoutes. The plugin receives no permission to mutate Gateways or GatewayClasses. Cluster-wide route access is accepted because a single controller supports application namespaces across the cluster; separate namespace-scoped controllers were rejected earlier.

Each adopting application owns a stable Service, canary Service, Gateway attachment, and HTTPRoute. A managed HTTPRoute rule must contain both Service backendRefs. For a `setWeight: N` step, the plugin writes canary weight `N` and stable weight `100-N`; Cilium Envoy enforces those request-routing proportions. Rules without both backends remain untouched, and the Rollout fails visibly when no matching rule exists.

Using native replica weighting alone was rejected because it cannot provide deterministic request-routing weights. Direct release-URL plugin downloads were rejected because they add runtime network availability and executable supply-chain risk.

### Treat analysis templates as application-owned policy

Document `AnalysisTemplate` and `ClusterAnalysisTemplate` examples that query `http://vmsingle-vmks.monitoring.svc.cluster.local:8428`. Do not install a universal success query: metric names, thresholds, sampling intervals, and failure limits are application-specific. The platform supplies the controller and reachable metrics backend; each adopting workload owns its analysis policy in Git.

Controller metrics are exposed through a Service. Integration with the existing VictoriaMetrics scraping model should use a `VMServiceScrape` only if the observability CRD is present; it must not make initial controller installation depend on observability reconciliation order.

### Validate packaging and both cluster renders offline

The wrapper chart includes `Chart.yaml`, `Chart.lock`, the unmodified packaged dependency, shared `values.yaml`, pinned plugin image configuration, plugin RBAC, and environment-specific overrides only where sizing differs. Add the component to the platform values and extend `apps/bootstrap/validate.sh` so linting and rendering cover the wrapper plus dev and prod roots. Render checks verify the init container, local plugin registration, shared volume, least-privilege HTTPRoute RBAC, and environment replica counts. Documentation includes explicit kubeconfig examples for both clusters and warns that sync waves on separate Argo CD Applications do not create a hard readiness dependency.

## Risks / Trade-offs

- **[CRDs exist before the controller is ready]** → Document controller readiness as a prerequisite for application adoption and verify the controller after platform sync.
- **[Argo CD prunes or removes cluster-scoped resources unexpectedly]** → Retain CRDs on uninstall and document the staged removal procedure.
- **[The plugin is an Argo Project Labs component rather than core Rollouts]** → Pin both plugin version and image digest, render its configuration offline, and test compatibility in dev before prod.
- **[Broad HTTPRoute access lets the controller patch routes cluster-wide]** → Limit verbs and resources, grant no Gateway/GatewayClass mutation, and configure Rollouts to name only their application-owned routes.
- **[Malformed HTTPRoutes stall a canary]** → Document and validate the required rule containing both stable and canary backendRefs; treat visible rollout failure as safer than silently shifting the wrong route.
- **[Weighted routing is statistically proportional rather than an exact request count]** → Describe weights as routing proportions and validate the HTTPRoute state directly during smoke testing.
- **[A bad shared chart update affects both clusters]** → Keep the dependency pinned, render both environments offline, and promote changes through dev before prod operationally.
- **[Analysis queries fail when VictoriaMetrics is unavailable]** → Require explicit failure limits and intervals in application-owned templates; failed analysis follows the Rollout's declared failure behavior.
- **[Two prod replicas increase resource use]** → Apply small explicit resources; only the elected leader performs reconciliation.
- **[Removing the controller strands active Rollouts]** → Treat uninstall as a migration requiring active Rollouts to become stable or return to Deployments first.

## Migration Plan

1. Add and validate the pinned wrapper chart, Gateway API plugin image/configuration, least-privilege RBAC, and platform Application definition without adding production application Rollout resources.
2. Sync dev and verify CRDs, controller readiness, local plugin loading, RBAC, and controller metrics.
3. Run a disposable dev smoke test whose stable/canary Services share an HTTPRoute rule, and verify declared canary steps produce the expected complementary backend weights through promotion and abort.
4. Sync prod and verify both controller replicas, leader election, plugin loading, CRDs, RBAC, and metrics.
5. Validate a VictoriaMetrics-backed analysis in dev before applications rely on automated analysis in prod.
6. Allow applications to migrate individually through their own reviewed changes.

Rollback before application adoption consists of removing the component from the platform configuration and pruning the controller while retaining CRDs. After adoption, rollback requires first stabilizing or migrating every Rollout resource; CRDs are removed only through an explicit, separately reviewed action.
