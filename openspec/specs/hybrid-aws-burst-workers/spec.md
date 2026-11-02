# Cloud worker capacity Specification

## Purpose

Provide independent Talos environments with fixed Proxmox dev capacity and bounded GCP production worker groups managed by Kubernetes Cluster Autoscaler.

## Requirements

### Requirement: Fixed Proxmox capacity
Dev SHALL preserve its existing Proxmox inventory and local GPU. It SHALL provision no cloud workers, cloud identity, or node autoscaler. Prod SHALL use a separate Talos identity on GCP and SHALL NOT depend on Proxmox connectivity.

#### Scenario: Apply dev without cloud credentials
- **WHEN** the dev cluster and platform are applied with Proxmox/Doppler credentials
- **THEN** they do not require AWS or GCP credentials and do not install Karpenter or Cluster Autoscaler

### Requirement: Preserved production baseline
Prod SHALL use one fixed On-Demand `e2-standard-4` control-plane/workload VM and three initial On-Demand `e2-standard-4` workers in `us-central1-a`. Each machine SHALL provide 4 vCPU and 16 GiB RAM. Kubernetes SHALL remain v1.37.2 and Cluster Autoscaler SHALL use the matching 1.37 minor release with a pinned image digest.

#### Scenario: Fresh deployment
- **WHEN** prod is created from empty state
- **THEN** one fixed control plane and three CPU workers are provisioned while the Spot group starts at zero

### Requirement: Bounded autoscaled groups
OpenTofu SHALL own GCE instance templates and Managed Instance Groups. Cluster Autoscaler SHALL be the sole autoscaler for these groups, with CPU and optional Spot bounds taken from the production inventory. No GCE metrics-based autoscaler SHALL compete for group size. OpenTofu SHALL ignore target-size drift after creation. Template updates SHALL NOT force-replace existing workers.

#### Scenario: Pending workload
- **WHEN** eligible pending pods cannot fit existing allocatable resources
- **THEN** Autoscaler attempts to grow a compatible configured group within its bounds

#### Scenario: Reconcile after scale-out
- **WHEN** OpenTofu applies after Autoscaler has grown a group
- **THEN** it does not reset the group to its initial size

#### Scenario: Scale from zero
- **WHEN** a workload selects the empty Spot group
- **THEN** Autoscaler can model its labels and Talos resource reservations from template metadata and request Spot workers

#### Scenario: Spot capacity unavailable
- **WHEN** no Spot VM can be allocated within quota/capacity
- **THEN** the selected workload stays pending without silently falling back to On-Demand capacity

#### Scenario: Idle group
- **WHEN** nodes become eligible for scale-down and drain constraints permit removal
- **THEN** Autoscaler removes workers without reducing the CPU group below two or autoscaling the fixed control plane

### Requirement: Talos bootstrap and cloud identity
GCE instances SHALL boot a pinned Talos GCP image and consume their machine configuration through `user-data`. Template `kube-env` metadata SHALL advertise labels and 500m CPU/1536 MiB memory reservations matching Talos system/kubelet reservations. Talos CCM SHALL initialize GCE provider IDs; Cilium SHALL initialize pod networking. Node identities SHALL have no application permissions.

#### Scenario: Worker boots
- **WHEN** a new managed worker starts
- **THEN** it joins the production Talos identity, receives a GCE provider ID and becomes schedulable after networking and cloud initialization

### Requirement: Independent cloud connectivity
Prod SHALL use same-VPC node connectivity and its private API endpoint for workers, with Cilium and KubePrism. The public API/Talos endpoint SHALL have a stable reserved address and accept only explicit management IPv4 CIDRs of /24 or narrower. Production SHALL NOT require KubeSpan to dev.

#### Scenario: Proxmox unavailable
- **WHEN** Proxmox is offline
- **THEN** production workers can still join their own control plane and access production storage

#### Scenario: Unrestricted management access requested
- **WHEN** management CIDRs include 0.0.0.0/0
- **THEN** validation rejects the configuration

### Requirement: Storage follows environment capabilities
Dev SHALL use local-path as its sole default StorageClass. Prod SHALL use expandable cloud-block storage backed by GCE PD or AWS EBS through CSI with WaitForFirstConsumer and Retain as its sole default. CSI SHALL run its node plugin on all production nodes, including the workload-bearing control plane. Stateful applications SHALL select On-Demand capacity. CNPG SHALL remain single-instance and SHALL NOT be described as highly available.

#### Scenario: Worker replaced
- **WHEN** an On-Demand worker with a Persistent Disk claim is replaced
- **THEN** a same-zone replacement can reattach the existing disk after safe detachment

### Requirement: Scoped identities and offline teardown
CI SHALL use production-only GitHub Workload Identity Federation. Autoscaler and CSI SHALL use separate purpose-scoped GCP credentials, independent of object consumers and permissionless node accounts. Normal cluster teardown SHALL remove managed worker groups and their instances without Kubernetes access while retaining persistent disks. Explicit purge SHALL delete only environment-labeled disks/snapshots. Foundation object buckets SHALL remain separately protected.

#### Scenario: Unreachable Kubernetes API
- **WHEN** the cluster is destroyed with Kubernetes unavailable
- **THEN** GCP deletes its managed worker groups and instances before networking is removed, and platform state resets only after successful cleanup

### Requirement: Validation and production deployment
Static CI SHALL validate roots and charts without remote state or deployment secrets. Trusted repository PRs SHALL deploy dev and independently plan prod; fork PRs SHALL validate only. Main SHALL deploy dev only, with production apply/destroy available through manual dispatch on main. Argo applications SHALL retain the selected revision.

#### Scenario: Trusted pull request
- **WHEN** a trusted repository PR passes lint
- **THEN** dev is deployed and production is planned without a production apply

### Requirement: Optional equivalent AWS deployment
The three foundation, cluster and platform layers SHALL select one production cloud using cloud_provider, defaulting to GCP. AWS SHALL use a fixed m6a.xlarge control plane and three initial m6a.xlarge CPU workers, matching the GCP baseline. CPU ASGs SHALL have bounds 3–4 and optional Spot ASGs 0–4, with Cluster Autoscaler owning desired capacity. AWS SHALL use EBS CSI through the same cloud-block StorageClass and share the cloud credential, storage and node-label contracts. No Karpenter resources SHALL be installed. Cloud selection SHALL target fresh deployments rather than state or data migration.

#### Scenario: Default provider selected
- **WHEN** foundation and production use their default cloud_provider
- **THEN** no AWS resources are created or AWS credentials required

#### Scenario: Fresh AWS deployment selected
- **WHEN** cloud_provider is aws with a current Talos AMI and AWS credentials
- **THEN** the existing roots and CI workflow provision AWS foundation, Talos cluster, bounded ASGs and the corresponding autoscaler and storage components
