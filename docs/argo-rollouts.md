# Argo Rollouts progressive delivery

Argo CD runs centrally in the `argocd` management cluster, but Argo Rollouts
reconciliation is cluster-local. Argo CD creates an `argo-rollouts` Application
for each registered workload cluster; the controllers and CRDs run in `dev` and
`prod`. No Rollouts controller or CRDs are installed in the `argocd` cluster.

The platform installs one controller replica in dev and two leader-electing
replicas in prod. It also installs the pinned `argoproj-labs/gatewayAPI` plugin.
The plugin binary is copied from a digest-pinned image at pod initialization; the
controller does not download executable code at runtime.

## Workload contract

Blue-green Rollouts need active and preview Services. A Cilium-routed canary
needs all of the following in the application namespace:

- a stable Service and a canary Service;
- a Cilium `Gateway` (or permission to attach to an existing Gateway);
- an `HTTPRoute` rule containing both Services as backendRefs; and
- a Rollout whose `trafficRouting.plugins.argoproj-labs/gatewayAPI` block names
  that HTTPRoute.

See [argo-rollouts-canary.yaml](examples/argo-rollouts-canary.yaml) for a complete
Service, HTTPRoute, AnalysisTemplate, and Rollout example. Its `Gateway` is
intentionally application-owned and is not included in the example.

A `setWeight: 10` step sets the stable backend weight to 90 and the canary to
10; `setWeight: 25` produces 75/25, and `setWeight: 50` produces 50/50. These
are request-routing proportions enforced by Cilium Envoy, not guarantees about
an exact request count in a small sample.

The plugin changes only HTTPRoute rules that contain both named Services. It
leaves unrelated rules, Gateways, and GatewayClasses unchanged. If no matching
rule exists, the routing step fails visibly and the Rollout does not silently
advance.

### Argo CD difference handling

The Rollouts controller, not Git, owns backend weights while a canary is active.
The Argo CD Application that manages an application HTTPRoute must include:

```yaml
spec:
  ignoreDifferences:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      jqPathExpressions:
        - .spec.rules[].backendRefs[].weight
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true
```

Without this setting, Argo CD self-healing can reset weights while Rollouts is
progressing the canary.

## Analysis with VictoriaMetrics

Each workload cluster exposes a Prometheus-compatible endpoint at
`http://vmsingle-vmks.monitoring.svc.cluster.local:8428`. The example template
uses `vector(1)` only to prove connectivity and analysis mechanics. Replace it
with an application-specific query and review the interval, count, success
condition, and failure limit before production use. Analysis policy belongs to
the adopting application and remains in Git.

## Operations

Always select a workload kubeconfig explicitly. Substitute the application
namespace and Rollout name where shown.

```bash
# Controller and plugin readiness in dev
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n argo-rollouts rollout status deploy/argo-rollouts
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n argo-rollouts logs deploy/argo-rollouts | grep 'argoproj-labs/gatewayAPI'

# Controller readiness in prod
kubectl --kubeconfig "$HOME/.kube/talos-prod.yaml" \
  -n argo-rollouts rollout status deploy/argo-rollouts
kubectl --kubeconfig "$HOME/.kube/talos-prod.yaml" \
  -n argo-rollouts logs deploy/argo-rollouts | grep 'argoproj-labs/gatewayAPI'
kubectl --kubeconfig "$HOME/.kube/talos-prod.yaml" \
  -n example get rollout,analysisrun,httproute

# Inspect a Rollout, analyses, route weights, pods, and recent events
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n example get rollout example -o yaml
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n example get analysisrun
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n example get httproute example -o yaml
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n example get pods -l app=example
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" \
  -n example get events --sort-by=.lastTimestamp

# With the kubectl argo rollouts plugin installed
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" argo rollouts \
  -n example get rollout example --watch
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" argo rollouts \
  -n example promote example
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" argo rollouts \
  -n example abort example
kubectl --kubeconfig "$HOME/.kube/talos-dev.yaml" argo rollouts \
  -n example restart example
```

Use the corresponding `talos-prod.yaml` kubeconfig for prod. Argo CD can also
invoke supported Rollout resource actions, but the controller and route state
must still be inspected in the destination workload cluster.

## Removal

The chart marks all Rollouts CRDs with `helm.sh/resource-policy: keep` and
`argocd.argoproj.io/sync-options: Delete=false,Prune=false`; pruning the
component therefore removes the controller but retains the APIs. Removal is
still a staged migration:

1. Stop introducing new Rollout resources.
2. Allow active Rollouts to reach a stable state, then migrate them back to
   Deployments or deliberately delete them.
3. Confirm no Rollout, AnalysisRun, AnalysisTemplate, ClusterAnalysisTemplate,
   or Experiment resources remain.
4. Remove the Argo Rollouts component and controller.
5. Remove the CRDs only in a separately reviewed operation, if desired.

Deleting a CRD deletes every custom resource of that kind. Never delete the
Rollouts CRDs as an ordinary uninstall shortcut.
