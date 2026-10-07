## MODIFIED Requirements

### Requirement: Single declarative owner per component
Each infrastructure resource, cluster component, and secret SHALL have exactly one declarative owner:
- the foundation root owns account, identity, and secret-store setup;
- the cluster root owns machines and generated credentials;
- the platform root owns Gateway API CRDs, Cilium, secret-store bootstrap credentials, Karpenter and Argo CD with its AppProject, root Application and UI LoadBalancer Service;
- the environment's Argo CD owns Istio, the Cloudflare operator/CRDs/ClusterTunnel, the Grafana UI LoadBalancer Service and everything else.

No component MAY be managed by both OpenTofu and Argo CD. No UI Gateway or HTTPRoute SHALL be rendered by the bootstrap chart.

Gateway API CRDs SHALL be installed from a pinned Helm chart archive committed to Git. Cilium SHALL use `kube-system` for its namespaced resources. Charts and releases SHALL handle any additional namespace they require declaratively; provisioning MUST NOT create per-component namespaces through scripts. Cluster-scoped Cilium resources remain cluster-scoped.

#### Scenario: Pre-GitOps components
- **WHEN** the platform root is applied to an environment
- **THEN** it installs Gateway API CRDs, Cilium, the bootstrap token Secret, Karpenter and Argo CD with its root Application and UI LoadBalancer Service, without a Gateway

#### Scenario: Drift on an Argo-owned component
- **WHEN** an Argo-owned component is changed in Git
- **THEN** only Argo CD reconciles it, and the next OpenTofu plan shows no change for it

#### Scenario: UI publishing
- **WHEN** Cilium's IPAM and L2 resources reconcile
- **THEN** Argo CD and Grafana Services receive their reserved LAN IPs and the Cloudflare operator remains independent
