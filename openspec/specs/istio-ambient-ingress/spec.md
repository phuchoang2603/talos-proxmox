# istio-ambient-ingress Specification

## Purpose

Provide optional Istio ambient mesh and Gateway API ingress while Cilium continues to handle networking and Talos KubeSpan connects hybrid nodes. Platform UIs use direct LoadBalancer Services.

## Requirements

### Requirement: Cilium remains the networking provider
Each environment SHALL run Cilium as CNI, kube-proxy replacement, LB IPAM and L2 announcer. Cilium MUST NOT deploy SPIRE/mutual authentication, WireGuard, Envoy/L7 proxy or its Gateway API controller. Cilium L3/L4 policy SHALL remain available.

#### Scenario: Fresh cluster
- **WHEN** an environment is created from empty state
- **THEN** Cilium provides pod and Service connectivity without its service-mesh components

### Requirement: Istio ambient remains opt-in
Each environment SHALL run one GitOps-owned umbrella Istio chart containing pinned base, istiod, CNI and ztunnel subcharts. The Istio Gateway API controller SHALL remain available for future application ingress; no platform UI SHALL require an Istio Gateway. Namespace enrollment SHALL be explicit.

#### Scenario: Namespace not enrolled
- **WHEN** a workload namespace is not explicitly enrolled in ambient
- **THEN** its traffic is not assumed to have Istio mTLS

### Requirement: Platform UIs use direct LoadBalancer Services
Dev/prod Argo CD and prod HyperDX SHALL each expose only their HTTP UI port through dedicated Cilium LB IPAM/L2-backed LoadBalancer Services. Their original ClusterIP Services SHALL remain internal. UI access MUST NOT depend on Gateway, HTTPRoute or Cloudflare TunnelBinding resources. Cloudflare operator CRDs MUST remain owned by its GitOps chart, not by OpenTofu.

#### Scenario: Bootstrap before the LB pool
- **WHEN** OpenTofu installs Argo CD and its UI Service before the Cilium IP pool and L2 policy converge
- **THEN** Argo CD reconciles internally, remains accessible by port-forward and obtains its requested LAN IP once Cilium is ready

#### Scenario: Prod observability
- **WHEN** prod observability reconciles
- **THEN** HyperDX is available at its reserved LAN IP through UI port 80 without exposing OpAMP

### Requirement: AWS KubeSpan remains operational
The Talos KubeSpan and KubePrism configuration for on-premises nodes and AWS Karpenter workers SHALL remain enabled and independent of Cilium's WireGuard setting. Cilium's pod MTU SHALL account for VXLAN traffic crossing the KubeSpan overlay.

#### Scenario: Worker joins
- **WHEN** a Karpenter worker joins over KubeSpan
- **THEN** its host API access and cross-site pod traffic remain functional without Cilium WireGuard
