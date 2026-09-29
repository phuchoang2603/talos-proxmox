## MODIFIED Requirements

### Requirement: Fixed Proxmox capacity
The platform SHALL maintain Talos control planes and on-premises worker and GPU nodes as fixed Proxmox VMs. Cluster identity and credentials SHALL be shared by each environment’s fixed nodes and AWS workers. Scaling AWS workers MUST NOT change the fixed Proxmox inventory.

#### Scenario: Add AWS worker capacity
- **WHEN** AWS burst infrastructure is deployed to an environment
- **THEN** it joins the cluster without changing fixed Proxmox capacity or requiring persistent volumes

### Requirement: Persistent storage remains on fixed Proxmox nodes
The platform SHALL provide `local-path` as the sole default StorageClass in both dev and prod, backed by the disk of the fixed Proxmox node where each volume is first provisioned. PVC-backed workloads in either environment MUST run on fixed Proxmox nodes. The platform MUST NOT provision an AWS EBS CSI driver, `gp3` StorageClass, or any replicated block storage system, and MUST NOT create persistent volumes on autoscaled AWS workers.

#### Scenario: Default dev claim
- **WHEN** a dev workload requests a PVC without a StorageClass
- **THEN** it receives local-path storage and runs on a fixed Proxmox node

#### Scenario: Default prod claim
- **WHEN** a prod workload requests a PVC without a StorageClass
- **THEN** it receives local-path storage and runs on a fixed Proxmox node

#### Scenario: Volume node is unavailable
- **WHEN** the fixed Proxmox node holding a local-path volume is down
- **THEN** pods using that volume stay Pending rather than starting on another node without their data

#### Scenario: AWS worker scales up
- **WHEN** a new AWS worker registers in dev or prod
- **THEN** no persistent volume is provisioned on that worker

### Requirement: AWS burst capacity is stateless only
The platform SHALL allow AWS workers to run only explicitly opted-in workloads without PVCs or persistent-volume templates. AWS workloads MAY use disposable `emptyDir` scratch space; it MUST NOT be presented as persistent data. The platform MUST keep PVC-backed pods on Proxmox even if they request AWS capacity.

#### Scenario: Stateless workload bursts
- **WHEN** a pod without PVC dependencies explicitly opts into AWS worker capacity
- **THEN** it can schedule on an AWS worker and can be rescheduled without retaining node-local data

#### Scenario: PVC-backed workload requests AWS capacity
- **WHEN** a dev or prod local-path workload has a PVC and otherwise qualifies for AWS burst capacity
- **THEN** it cannot schedule on AWS and remains on fixed Proxmox capacity or visibly Pending

#### Scenario: AWS worker terminates
- **WHEN** an autoscaled AWS worker hosting a stateless workload is removed
- **THEN** its disposable scratch contents may be lost without deleting any persistent cluster data
