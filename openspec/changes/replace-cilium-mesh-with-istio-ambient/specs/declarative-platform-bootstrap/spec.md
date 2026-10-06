## MODIFIED Requirements

### Requirement: Script-free environment bring-up
The platform SHALL provision an environment from empty state to an eventually synced platform using Git, OpenTofu applies and Argo CD reconciliation alone. CI success SHALL mean the cluster and platform applies completed; full GitOps convergence occurs later and MUST NOT require an externally assigned UI IP.

#### Scenario: Fresh environment
- **WHEN** CI applies an environment's cluster and platform roots against empty state
- **THEN** Argo CD can reconcile enabled components internally without a manually created UI route

#### Scenario: Provisioning completes before GitOps convergence
- **WHEN** the cluster and platform applies succeed and the root Application is installed
- **THEN** provisioning CI succeeds without waiting for Istio, Cloudflare or Cilium L2 IP assignment to become healthy

#### Scenario: Repeat apply
- **WHEN** CI re-applies an unchanged environment
- **THEN** OpenTofu reports no changes to cluster components or secrets, and Argo CD applications stay Synced

### Requirement: Single declarative owner per component
Each infrastructure resource, cluster component and secret SHALL have exactly one declarative owner: the foundation root owns account and secret-store setup; the cluster root owns machines and generated credentials; the platform root owns Gateway API CRDs, Cilium, secret-store bootstrap credentials, Karpenter and Argo CD with its AppProject, root Application and UI LoadBalancer Service; Argo CD owns Istio, the Cloudflare operator/CRDs/ClusterTunnel and the HyperDX UI LoadBalancer Service. No UI Gateway or HTTPRoute SHALL be rendered by the bootstrap chart.

#### Scenario: Pre-GitOps components
- **WHEN** the platform root is applied to an environment
- **THEN** it installs Gateway API CRDs, Cilium, the bootstrap token Secret, Karpenter and Argo CD with its root Application and UI LoadBalancer Service, without a Gateway

#### Scenario: Drift on an Argo-owned component
- **WHEN** an Argo-owned component is changed in Git
- **THEN** only Argo CD reconciles it, and the next OpenTofu plan shows no change for it

#### Scenario: UI publishing
- **WHEN** Cilium's IPAM and L2 resources reconcile
- **THEN** Argo CD and HyperDX Services receive their reserved LAN IPs and the Cloudflare operator remains independent
