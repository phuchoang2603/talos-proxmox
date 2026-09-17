# Cluster applications

Configuration is grouped by component. Bootstrap owns networking, storage,
metrics-server, GPU support, and Argo CD itself. Argo CD owns the workload
clusters' database operators, External Secrets, and observability.

```text
apps/
  bootstrap/                  # Ordered installation and shared Helm helpers
  components/
    <component>/
      release.json            # Bootstrap chart source and pinned version
      values.yaml             # Shared Helm overrides
      environments/<env>/     # Environment values and resources, when needed
      resources/              # Additional component resources
      Chart.yaml              # Argo CD wrapper chart, where used
      Chart.lock
      charts/                 # Pinned .tgz packages
      templates/
  argocd/
    platform/                 # App-of-apps chart for one workload cluster
    roots/dev.yaml            # Manually applied dev root
    roots/prod.yaml            # Manually applied prod root
```

Each component uses the files it needs. Bootstrap components declare their chart
source and version in `release.json`; Helm overrides live beside it. Optional
`environments/<env>/values.yaml` files override the shared values. Argo CD
components use wrapper charts with pinned, packaged dependencies, allowing CI
to render them without fetching chart dependencies. Additional resources stay
with their component rather than in a separate global manifests directory.

## Bootstrap

Run `bootstrap/bootstrap.sh` with `KUBECONFIG` and `ENV_NAME` (`dev`, `prod`, or
`argocd`). It uses the corresponding Terraform inventory and installs:

1. Gateway API CRDs and Cilium, without waiting for SPIRE storage.
2. Cilium network resources and node readiness checks.
3. Longhorn when inventory nodes have role `longhorn`; otherwise the packaged
   local-path-provisioner Helm chart. Both provide the default StorageClass.
4. The remaining Cilium/SPIRE readiness checks, then metrics-server.
5. NVIDIA GPU Operator and DRA driver when inventory nodes have PCI devices.

Longhorn requires `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, and
`LONGHORN_AWS_SECRET_ACCESS_KEY`. Local-path uses `/opt/local-path-provisioner`,
the `local-path` StorageClass, and `WaitForFirstConsumer`. Its namespace receives
privileged Pod Security labels for helper pods. Local-path is node-local storage.

`bootstrap/bootstrap-argocd.sh` runs only with `ENV_NAME=argocd`, after the main
bootstrap. It installs Argo CD and registers dev and prod using their kubeconfigs
from Doppler. Required: `KUBECONFIG` and `DOPPLER_READ_TOKEN`, a project read token
with access to both remote configs. Provision dev and prod first.
`DOPPLER_PROJECT` defaults to `talos-proxmox`.

All bootstrap Helm components install directly from `.tgz` files in their
`charts/` directory. `release.json` records the selected archive in `chartPath`,
its version, and its upstream source. Bootstrap does not add Helm repositories
or download charts. Container images still come from their registries; Gateway
API CRDs are fetched separately at their pinned version.

To upgrade a repository chart, download the desired package, update `version`
and `chartPath` in its `release.json`, remove the superseded archive, and validate:

```bash
helm pull longhorn --repo https://charts.longhorn.io --version 1.11.1 \
  --destination apps/components/longhorn/charts
```

For NVIDIA charts, packages are also available directly from
`https://helm.ngc.nvidia.com/nvidia/charts/<chart>-<version>.tgz`.
Local-path uses a package built from its pinned official chart source; see
[`components/local-path-provisioner/README.md`](components/local-path-provisioner/README.md).
Chart versions are determined by the committed packages, rather than environment
variable overrides. Gateway API retains its `GATEWAY_API_VERSION` override.

## Manual Argo CD deployment

Once Argo CD is installed and the desired remote cluster is registered, apply
its root to the management cluster:

```bash
# Dev only
kubectl --kubeconfig "$HOME/.kube/talos-argocd.yaml" apply --server-side \
  -f apps/argocd/roots/dev.yaml

# Prod only, when ready
kubectl --kubeconfig "$HOME/.kube/talos-argocd.yaml" apply --server-side \
  -f apps/argocd/roots/prod.yaml
```

Each root creates five Applications targeting only its named cluster:

| Component | Namespace |
| --- | --- |
| External Secrets | operators |
| CloudNativePG | operators |
| Strimzi | operators |
| MongoDB operator | operators |
| Observability (VictoriaMetrics Operator, Grafana, monitoring stack) | monitoring |

The roots track this repository's `main` branch. Publish the chart files there
before applying. Applying a root enables automatic sync, pruning, and self-healing
for that environment. Application resources live in `argo-cd` on the management
cluster; their workloads run on the destination cluster. Each root's `cluster`
parameter selects the destination and component environment values.

Provision the Doppler token as `operators/doppler-token` on each workload cluster.
Wait for operators and their CRDs to be healthy before deploying dependent
workloads. Sync waves do not order separate roots.

## Validation and CI

Run `devenv shell -- apps/bootstrap/validate.sh` from the repository root.
It checks shell syntax and release metadata and lints/renders both platform
configurations, all packaged charts, and component environment overlays.

GitHub Actions runs the same validation. Provisioning CI still bootstraps cluster
infrastructure, installs Argo CD on the management cluster, and registers remote
clusters. It **does not apply either platform root**.
