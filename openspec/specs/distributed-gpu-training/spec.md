# distributed-gpu-training Specification

## Purpose
Retain fixed local GPU capacity and the explicit NVIDIA DRA runtime contract, with one fixed on-demand GCP GPU worker.

## Requirements

### Requirement: Dedicated cloud GPU capacity
When gcp_gpu_enabled is true, prod SHALL provision a dedicated managed instance group targeting one on-demand g2-standard-4 worker with one NVIDIA L4. Cluster Autoscaler SHALL register the GPU group with minimum and maximum size one. The worker SHALL use a Talos image with matching NVIDIA kernel and toolkit extensions, dedicated GPU placement labels and a workload taint. Cloud GPU workloads SHALL remain pending rather than use CPU workers or dev GPUs when quota or capacity is unavailable. Dev SHALL retain local GPU allocation.

#### Scenario: Fixed prod GPU enabled
- **WHEN** the production inventory enables gcp_gpu_enabled and quota is available
- **THEN** the dedicated GPU group targets one on-demand L4 worker and is registered with Cluster Autoscaler at bounds of one to one

#### Scenario: GPU disabled
- **WHEN** gcp_gpu_enabled is false
- **THEN** no cloud GPU instance is provisioned and GPU claims remain pending without launching CPU workers to satisfy GPU capacity

#### Scenario: Capacity or quota failure
- **WHEN** no allowed zone can supply the required node
- **THEN** the reason is observable and the workload does not silently use local capacity or another topology

### Requirement: Verified accelerator readiness
GCP GPU workers SHALL use a pinned compatible Talos image and GPU stack. Readiness evidence SHALL include allocated-device execution and a framework forward/backward pass; node registration alone SHALL NOT establish training readiness.

#### Scenario: Worker joined but device unverified
- **WHEN** a worker has joined the cluster
- **THEN** readiness is claimed only after an allocated GPU completes a framework forward/backward pass

### Requirement: Distributed runtime handoff
The platform SHALL expose a versioned runtime and scheduling contract supporting one GPU rank on one eligible GPU node per job. Acceptance SHALL verify worker identity, allocated-device execution and timeout behavior. Multi-node collectives are not part of the contract.

#### Scenario: Single-node training step
- **WHEN** the acceptance workload executes
- **THEN** the allocated GPU completes a framework training step and identity evidence is retained

#### Scenario: Worker never becomes ready
- **WHEN** the required worker does not become ready before the configured deadline
- **THEN** the workload fails or is canceled with cleanup instead of hanging indefinitely

### Requirement: Bounded cloud lifecycle
The fixed GPU worker SHALL remain provisioned after jobs finish until explicitly disabled in the production inventory. GPU autoscaling and Spot GPU capacity SHALL remain disabled. Durable checkpoints SHALL reside in object storage.

#### Scenario: Training ends
- **WHEN** a GPU job finishes
- **THEN** its device claim can be released while the fixed GPU worker remains available

#### Scenario: Explicit GPU teardown
- **WHEN** gcp_gpu_enabled is disabled and the cluster configuration is applied
- **THEN** the GPU VM is removed while the fixed control plane, CPU baseline and Persistent Disk data remain

### Requirement: Local notebook GPU allocation
The dev RTX 5060 Ti SHALL remain usable through exclusive notebook allocation. Production training SHALL NOT claim it. Occupied local capacity SHALL leave another GPU notebook pending.

#### Scenario: Local GPU occupied
- **WHEN** a second notebook requests the exclusive GPU
- **THEN** it waits without silently substituting CPU training

#### Scenario: Local GPU is occupied
- **WHEN** another notebook requests the exclusively allocated device
- **THEN** it waits for GPU capacity without changing node-reported capacity or creating a local CPU training lane
