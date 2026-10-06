## Why

A fresh cluster can keep Cilium for pod networking and load balancing while using Istio ambient for opt-in service mesh. Platform UIs need only direct LAN LoadBalancer Services, not mesh gateways or Cloudflare tunnels.

## What Changes

- Keep Cilium CNI, kube-proxy replacement, L3/L4 policy, LB IPAM and L2 announcements; disable Cilium WireGuard, SPIRE/mutual authentication, Envoy/L7 proxy and Gateway API controller.
- Install pinned Istio base, istiod, CNI and ztunnel in one vendored Argo CD chart in dev and prod, without enrolling namespaces automatically.
- Expose dev/prod Argo CD and prod HyperDX on UI-only Cilium-allocated LoadBalancer Services at their reserved LAN IPs. Keep their existing ClusterIP Services internal and remove their Gateways, HTTPRoutes and TunnelBindings.
- Retain Gateway API CRDs for future Istio ingress. Keep Cloudflare operator CRDs with its GitOps-managed chart, without preinstalling them in OpenTofu. Cap Cilium pod MTU for VXLAN over Talos KubeSpan without changing Karpenter or Talos networking.

## Capabilities

### New Capabilities

- `istio-ambient-ingress`: Istio ambient mesh and available Gateway API ingress on clusters that continue to use Cilium for CNI and LB/L2 networking.

### Modified Capabilities

- `declarative-platform-bootstrap`: Bootstrap Argo CD with a UI-only LoadBalancer Service; publish HyperDX with the observability chart.

## Impact

Changes the OpenTofu-owned Cilium and Gateway API charts, the Argo CD component catalog, platform UI Services and existing architecture/access documentation. Neither cluster is applied to by these source edits.
