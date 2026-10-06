## Context

OpenTofu installs Gateway API CRDs and Cilium before Argo CD bootstrap. The bootstrap chart creates a UI LoadBalancer Service; Argo CD later installs the Cilium LB pool/L2 policy, the single Istio Application, observability and the independent Cloudflare operator/CRDs. This change does not provision a cluster or update unrelated applications.

## Decisions

1. **Cilium remains the primary CNI.** Keep kube-proxy replacement, LB IPAM/L2 and L3/L4 policies. Disable its Gateway controller, Envoy/L7 proxy, SPIRE/authentication and encryption. `cni.exclusive: false` and `socketLB.hostNamespaceOnly: true` allow Istio CNI/ambient chaining. Limit the pod MTU to 1370 for VXLAN over the default 1420-byte Talos KubeSpan overlay; verify cross-site traffic after provisioning. Keep Talos KubeSpan and KubePrism enabled on Proxmox and AWS nodes and AWS UDP 51820 open.
2. **One Istio chart.** Vendor version-pinned base, istiod, CNI and ztunnel subcharts under a single Argo CD-owned Helm release in each cluster. Namespace enrollment is explicit. Keep the OpenTofu-owned pinned Gateway API CRDs for future Istio-class application ingress; install no platform UI Gateway/HTTPRoute.
3. **UI-only LoadBalancer Services.** The OpenTofu-owned bootstrap chart renders `argocd-ui` on `10.69.11.254` (dev) and `10.69.12.254` (prod). The GitOps-owned observability chart renders `hyperdx-ui` on `10.69.12.128` (prod). Each Service requests its IP from Cilium LB IPAM through `lbipam.cilium.io/ips`; the existing Cilium L2 policy announces the address. Only UI port 80 is exposed, preserving Argo CD and HyperDX's existing ClusterIP Services and keeping HyperDX OpAMP internal. Prod OTLP retains its separate `10.69.12.129` address. The Cloudflare operator retains its vendored CRDs and has no dependency from these UIs.
4. **Bootstrap remains asynchronous.** The Argo CD UI Service exists before the GitOps-owned Cilium pool/L2 policy. The bootstrap Helm release does not wait for an external IP; Argo CD reconciles internally and a port-forward is available until Cilium assigns and announces the address. Argo CD and HyperDX use HTTP LAN URLs; do not claim TLS or public access for these Services.

## Risks / Checks

- KubeSpan runs independently of Cilium WireGuard, but a cross-site pod MTU mismatch or broken Talos discovery can still disrupt AWS workers. Verify KubeSpan peers, node readiness, pod traffic across sites and Karpenter scale-from-zero after provisioning.
- LoadBalancer IP assignment is asynchronous. Check the reserved addresses are unclaimed, Cilium LB pool/L2 policy is Ready, and only UI ports are exposed.
- These source edits do not run a platform apply or modify a live cluster.
