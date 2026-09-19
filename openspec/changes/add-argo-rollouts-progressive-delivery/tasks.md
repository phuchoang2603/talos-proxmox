## 1. Package the Argo Rollouts component

- [x] 1.1 Create the `apps/components/argo-rollouts` wrapper chart with a pinned upstream `argo-rollouts` dependency, generate and commit its lock file and unmodified chart archive, and verify `helm dependency build` reports no dependency drift.
- [x] 1.2 Add shared values for cluster-scoped RBAC, CRD installation and retention, disabled dashboard, controller resources, and metrics Service exposure; verify `helm template --include-crds` renders the controller, cluster RBAC, metrics Service, and all expected Rollouts CRDs.
- [x] 1.3 Pin the Gateway API traffic-router plugin container image by version and immutable digest, configure an init container to copy its binary into a shared volume, and register `argoproj-labs/gatewayAPI` from the local `file://` path; verify the rendered controller has the init container, shared volume mounts, and no runtime plugin download URL.
- [x] 1.4 Add wrapper-owned plugin RBAC limited to reading Services and getting, listing, updating, and patching HTTPRoutes; verify rendered rules contain no mutation permission for Gateways or GatewayClasses.
- [x] 1.5 Add dev and prod value overlays with one controller replica in dev and two leader-electing replicas with scheduling spread in prod; verify rendered Deployment replica counts and prod leader-election arguments.

## 2. Integrate with multi-cluster Argo CD

- [x] 2.1 Add the Argo Rollouts component to the platform app-of-apps values with destination namespace `argo-rollouts`, an early sync wave, the stable release name, and per-cluster value files; verify Helm rendering creates `dev-argo-rollouts` and `prod-argo-rollouts` Applications targeting their respective registered clusters.
- [x] 2.2 Confirm the generated component Applications retain automated sync, pruning, self-healing, namespace creation, and server-side apply settings; verify these fields in the rendered dev and prod Application manifests.
- [x] 2.3 Verify the management-cluster root manifests do not create a local Argo Rollouts controller or CRDs by rendering both roots and checking that only remote destination Applications are added.

## 3. Add validation coverage

- [x] 3.1 Extend offline component validation so Argo Rollouts is linted and rendered in its real namespace with both environment overlays and CRDs included; verify intentionally invalid values or missing plugin configuration cause the validation command to fail.
- [x] 3.2 Add rendered-manifest assertions for the pinned plugin image, local plugin path, shared volume, HTTPRoute-only mutation RBAC, and dev/prod replica counts; verify the assertions fail when each expected field is removed from a test render.
- [x] 3.3 Run `devenv shell -- apps/bootstrap/validate.sh` and verify all bootstrap scripts, wrapper charts, plugin assertions, and dev/prod platform renders pass without cluster access or chart downloads.
- [x] 3.4 Run repository formatting and consistency checks, including `git diff --check`, and verify only the planned component, platform, validation, documentation, and OpenSpec files changed.

## 4. Document adoption and operations

- [x] 4.1 Update the application architecture documentation to explain central Argo CD ownership versus cluster-local Rollouts reconciliation, and verify it explicitly states that no controller is installed in the `argocd` management cluster.
- [x] 4.2 Document blue-green and Cilium Gateway API-weighted canary prerequisites, including the stable Service, canary Service, and HTTPRoute rule containing both backendRefs; verify the example maps each `setWeight` value to complementary stable/canary route weights.
- [x] 4.3 Document that the plugin changes only matching HTTPRoute rules, leaves Gateways and unrelated rules untouched, and fails a rollout with no matching stable/canary rule; verify these safety behaviors are explicit in the Rollouts section.
- [x] 4.4 Add a VictoriaMetrics-backed `AnalysisTemplate` example using the workload-local `vmsingle-vmks.monitoring.svc.cluster.local:8428` endpoint, explicit intervals, success conditions, and failure limits; verify the example parses as valid YAML and references no environment-specific external address.
- [x] 4.5 Document controller readiness, plugin loading, HTTPRoute weights, Rollout/AnalysisRun inspection, promotion, abort, restart, and event commands for dev and prod using explicit kubeconfig paths; verify no operational example relies on the default kubeconfig.
- [x] 4.6 Document the staged uninstall procedure that preserves CRDs and requires Rollout migration before explicit CRD deletion; verify the procedure warns that deleting a CRD deletes its custom resources.

## 5. Verify deployment behavior

- [x] 5.1 Render and inspect the final chart artifacts to verify CRDs carry retention behavior and removal of the component would not implicitly prune adopted Rollout resources.
- [ ] 5.2 After deployment is separately authorized, synchronize dev and verify its Rollout APIs, single ready controller replica, successful local Gateway API plugin loading, and plugin RBAC before proceeding to prod.
- [ ] 5.3 After deployment is separately authorized, create a disposable dev Rollout with stable/canary Services and a Cilium HTTPRoute, then verify canary steps patch complementary backend weights, unrelated rules remain unchanged, abort restores stable routing, and all smoke-test resources are removed afterward.
- [ ] 5.4 After the dev smoke test passes and prod deployment is separately authorized, synchronize prod and verify its Rollout APIs, two ready controller replicas with leader election, successful plugin loading, and plugin RBAC while the `argocd` cluster has no Rollouts controller.
- [ ] 5.5 After deployment is separately authorized, verify the controller metrics endpoint is reachable in each workload cluster and record any follow-up needed for `VMServiceScrape` integration without making controller readiness depend on the observability operator.
