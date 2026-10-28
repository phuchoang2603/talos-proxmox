## MODIFIED Requirements

### Requirement: Cilium remains the networking provider
Cilium SHALL provide CNI and kube-proxy replacement in both clusters. LAN LoadBalancer IPAM, address pools and L2 announcements SHALL NOT be enabled in either environment. Cilium L3/L4 policy SHALL remain available without enabling its service mesh or Gateway controller.

#### Scenario: Cloud install
- **WHEN** prod networking converges
- **THEN** pod and Service connectivity works without LAN IP pools

#### Scenario: Fresh cluster
- **WHEN** an environment is created from empty state
- **THEN** Cilium provides pod and Service connectivity without its service-mesh components

### Requirement: Platform UIs use direct LoadBalancer Services
Both environments SHALL use ClusterIP Services and environment Cloudflare tunnels, with no LAN LoadBalancer Services. Both SHALL support management port-forward when public access is unavailable.

#### Scenario: Cloud UI
- **WHEN** prod converges
- **THEN** no UI waits for an unbacked LoadBalancer address

#### Scenario: Bootstrap before the LB pool
- **WHEN** Argo CD installs before public tunnel routes converge
- **THEN** it reconciles internally and supports port-forward without waiting for a LAN address

#### Scenario: Prod observability
- **WHEN** prod observability reconciles
- **THEN** Grafana is available through its ClusterIP, tunnel and management port-forward without a LAN LoadBalancer

### Requirement: AWS KubeSpan remains operational
Prod SHALL support same-VPC node/pod connectivity and local KubePrism without cross-site dependencies. MTU SHALL match the actual network. Dev MAY retain KubeSpan independently.

#### Scenario: Independent cloud connectivity
- **WHEN** dev is offline
- **THEN** prod pod communication and API reachability continue

#### Scenario: Worker joins
- **WHEN** a Karpenter worker joins prod
- **THEN** same-VPC host/pod connectivity and KubePrism work without cross-site KubeSpan
