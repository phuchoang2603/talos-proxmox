## MODIFIED Requirements

### Requirement: Per-cluster GitOps enablement
Each environment's Argo CD SHALL reconcile its components from one shared Git platform definition. Each component MUST declare which environments it runs on and MAY vary values per environment. Storage, GPU, burst, and ingress components MUST be enabled only on environments that have the corresponding nodes or needs.

#### Scenario: Storage selection
- **WHEN** the platform definition is reconciled
- **THEN** both dev and prod run local-path, neither runs Longhorn, and neither cluster has more than one default StorageClass

#### Scenario: Component disabled for an environment
- **WHEN** a component does not list an environment
- **THEN** that environment's Argo CD has no Application for it
