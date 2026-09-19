## Why

Dev and prod currently rely on standard Kubernetes workload updates, so deployments cannot use declarative canary or blue-green progression with automated analysis and rollback. Argo CD already manages both workload clusters centrally, making it the natural delivery path for installing a local Argo Rollouts controller in each cluster and syncing Rollout resources from Git.

## What Changes

- Add Argo Rollouts as an Argo CD-managed platform component for the `dev` and `prod` workload clusters.
- Install the Argo Rollouts CRDs and a controller in each workload cluster; do not run a central controller in the `argocd` management cluster.
- Enable declarative blue-green and canary workloads, including exact request-level canary weights through Cilium Gateway API and optional analysis against the existing Prometheus-compatible VictoriaMetrics endpoint.
- Install and pin the Argo Rollouts Gateway API traffic-router plugin with the RBAC required to update application-owned HTTPRoutes.
- Package and pin the upstream Helm dependency using the repository's existing component conventions.
- Extend offline validation and operational documentation to cover both cluster renders, controller readiness, rollout inspection, promotion, abort, and rollback.
- Keep migration of existing application Deployments to Rollouts outside this foundational change; applications can adopt the capability incrementally afterward.

## Capabilities

### New Capabilities

- `progressive-delivery`: Provides Argo CD-managed, cluster-local Argo Rollouts controllers and the contracts required for workload teams to use blue-green, Cilium Gateway API-weighted canary, and metric-assisted rollout strategies in dev and prod.

### Modified Capabilities

None.

## Impact

- Adds a new wrapper chart under `apps/components` and a new component entry in the platform app-of-apps configuration.
- Adds Argo Rollouts CRDs, controller workloads, Gateway API plugin RBAC, and related cluster-scoped resources to dev and prod.
- Adds an upstream Argo Rollouts Helm chart, controller image, and pinned Gateway API plugin image dependency.
- Extends `apps/bootstrap/validate.sh` and `apps/README.md` for rendering and operating the new component.
- Does not install Argo Rollouts in the management cluster and does not convert existing application manifests in this change.
