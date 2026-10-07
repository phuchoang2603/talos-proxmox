## MODIFIED Requirements

### Requirement: Platform UIs use direct LoadBalancer Services
Dev/prod Argo CD and prod Grafana SHALL each expose only their HTTP UI port through dedicated Cilium LB IPAM/L2-backed LoadBalancer Services. Their original ClusterIP Services SHALL remain internal. UI access MUST NOT depend on Gateway, HTTPRoute or Cloudflare TunnelBinding resources. Cloudflare operator CRDs MUST remain owned by its GitOps chart, not by OpenTofu.

#### Scenario: Bootstrap before the LB pool
- **WHEN** OpenTofu installs Argo CD and its UI Service before the Cilium IP pool and L2 policy converge
- **THEN** Argo CD reconciles internally, remains accessible by port-forward and obtains its requested LAN IP once Cilium is ready

#### Scenario: Prod observability
- **WHEN** prod observability reconciles
- **THEN** Grafana is available at its reserved LAN IP through UI port 80, and no other Grafana port is exposed on that address
