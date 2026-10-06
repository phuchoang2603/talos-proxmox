## 1. Fresh-Cluster Networking

- [x] 1.1 Verify pinned Istio/Gateway API sources and render their vendored charts.
- [x] 1.2 Keep Cilium CNI/LB IPAM/L2, disable mesh features, and account for VXLAN over KubeSpan without changing Talos or Karpenter.
- [x] 1.3 Pin Gateway API standard CRDs in the OpenTofu root.

## 2. GitOps Istio

- [x] 2.1 Consolidate pinned Istio base, istiod, CNI and ztunnel dependencies into one chart and retire their old wrappers.
- [x] 2.2 Register one privileged Istio Application per environment; verify the combined render and dependency lock.

## 3. UI LoadBalancers

- [x] 3.1 Remove Argo CD and HyperDX Gateways/HTTPRoutes and TunnelBindings; render dedicated UI-only LoadBalancer Services in bootstrap and observability at reserved addresses.
- [x] 3.2 Preserve original ClusterIP Services and their non-UI ports; verify selectors, backend ports, Cilium LB IP requests and LAN frontend URLs for both environments.
- [x] 3.3 Restore the GitOps-owned Cloudflare operator CRDs, remove OpenTofu preinstallation and verify no UI Service depends on Cloudflare.

## 4. Validation and Documentation

- [x] 4.1 Update architecture/access docs for one Istio chart, Cilium L2 UI Services and asynchronous bootstrap, without Cloudflare UI routes.
- [x] 4.2 Lint/render both environments, validate OpenTofu/OpenSpec and report that these edits did not apply to a live cluster.

Validation notes: all 22 repository charts linted, dev/prod manifests rendered, and the single Istio chart has four valid pinned dependencies. Argo CD and HyperDX UI LoadBalancer selectors and only-port-80 exposure match their running Deployment labels; their original ClusterIP Services and HyperDX OpAMP remain internal. Cilium LB IP requests preserve the original addresses, and the Cloudflare operator again owns its four CRDs. Platform OpenTofu validation and strict OpenSpec validation passed; this source edit did not run a cluster apply.
