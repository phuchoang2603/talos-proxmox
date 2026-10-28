## MODIFIED Requirements

### Requirement: Dedicated cloud GPU capacity
Prod SHALL expose an optional bounded GPU NodePool under the same Karpenter controller as CPU workers. It SHALL be disabled by default and idle at zero when enabled without jobs. Dev SHALL retain local GPU allocation.

#### Scenario: Default prod deployment
- **WHEN** no GPU pool has been explicitly enabled
- **THEN** no GPU instance is launched

#### Scenario: Train from zero cloud workers
- **WHEN** a single-GPU workload is submitted within configured limits
- **THEN** one eligible AWS node joins and provides GPU allocation without changing fixed Proxmox inventory

#### Scenario: Capacity or quota failure
- **WHEN** no allowed zone can supply the required node
- **THEN** the reason is observable and the workload does not silently use local capacity or another topology

### Requirement: Bounded cloud lifecycle
GPU capacity SHALL return to zero after bounded jobs finish. Durable checkpoints SHALL reside in object storage. GPU interruption recovery SHALL be verified before enabling Spot GPU training.

#### Scenario: Training ends
- **WHEN** the idle interval elapses
- **THEN** GPU workers terminate while CPU baseline and persistent storage remain available

#### Scenario: Finish or cancel distributed work
- **WHEN** training resources are removed and the idle interval elapses
- **THEN** GPU nodes terminate while the fixed control plane, CPU baseline and EBS data remain

### Requirement: Local notebook GPU allocation
The dev RTX 5060 Ti SHALL remain usable through exclusive notebook allocation. AWS training SHALL NOT claim it. Occupied local capacity SHALL leave another GPU notebook pending.

#### Scenario: Local GPU occupied
- **WHEN** a second notebook requests the exclusive GPU
- **THEN** it waits without silently substituting CPU training

#### Scenario: Local GPU is occupied
- **WHEN** another notebook requests the exclusively allocated device
- **THEN** it waits for GPU capacity without changing node-reported capacity or creating a local CPU training lane
