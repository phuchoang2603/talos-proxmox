## Purpose

Provide bounded, stateless AWS GPU workers for distributed training while retaining fixed local GPU capacity for interactive notebooks.

## ADDED Requirements

### Requirement: Dedicated cloud GPU capacity
The platform SHALL expose an opt-in GPU burst pool alongside existing CPU capacity. Initial acceptance SHALL provision an on-demand AWS GPU worker for a single-node job, and up to two such jobs MAY run concurrently without communicating with each other. Pool configuration SHALL declare finite resource limits, compatible instance types and a pause control.

#### Scenario: Train from zero cloud workers
- **WHEN** a single-GPU workload is submitted within configured limits
- **THEN** one eligible AWS node joins and provides GPU allocation without changing fixed Proxmox inventory

#### Scenario: Capacity or quota failure
- **WHEN** no allowed zone can supply the required node
- **THEN** the reason is observable and the workload does not silently use local capacity or another topology

### Requirement: Verified accelerator readiness
AWS GPU workers SHALL use a pinned compatible Talos image and GPU stack. Readiness evidence SHALL include allocated-device execution and a framework forward/backward pass; node registration alone SHALL NOT establish training readiness.

#### Scenario: Worker joined but device unverified
- **WHEN** a worker has joined the cluster
- **THEN** readiness is claimed only after an allocated GPU completes a framework forward/backward pass

### Requirement: Distributed runtime handoff
The platform SHALL expose a versioned runtime and scheduling contract supporting one GPU rank on one AWS node per job. Acceptance SHALL verify worker identity, allocated-device execution and timeout behavior. Multi-node collectives are not part of the contract.

#### Scenario: Single-node training step
- **WHEN** the acceptance workload executes
- **THEN** the allocated AWS GPU completes a framework training step and identity evidence is retained

#### Scenario: Worker never becomes ready
- **WHEN** the required worker does not become ready before the configured deadline
- **THEN** the workload fails or is canceled with cleanup instead of hanging indefinitely

### Requirement: Bounded cloud lifecycle
The GPU pool SHALL scale back to zero after workloads finish or are canceled. Disruption policy SHALL avoid voluntary removal during bounded training runs. Spot training SHALL remain disabled until checkpoint recovery and interruption handling are demonstrated.

#### Scenario: Finish or cancel distributed work
- **WHEN** training resources are removed and the idle interval elapses
- **THEN** cloud GPU instances and their Node objects are removed while controllers and persistent storage remain on fixed nodes

### Requirement: Local notebook GPU allocation
The fixed RTX 5060 Ti SHALL remain usable through the existing GPU allocation path for notebook experiments. Automated AWS training SHALL NOT claim that GPU, and unavailable exclusive allocation SHALL leave a notebook pending rather than substitute CPU fitting.

#### Scenario: Local GPU is occupied
- **WHEN** another notebook requests the exclusively allocated device
- **THEN** it waits for GPU capacity without changing node-reported capacity or creating a local CPU training lane
