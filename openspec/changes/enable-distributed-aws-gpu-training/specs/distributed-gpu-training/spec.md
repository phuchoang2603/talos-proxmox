## Purpose

Provide bounded, stateless AWS GPU workers for distributed training while retaining fixed local GPU capacity for interactive notebooks.

## ADDED Requirements

### Requirement: Dedicated cloud GPU capacity
The platform SHALL expose an opt-in GPU burst pool alongside existing CPU capacity. Initial acceptance SHALL provision two distinct on-demand AWS GPU workers in one selected availability zone in the existing Talos cluster. Pool configuration SHALL declare finite resource limits, compatible instance types and a pause control.

#### Scenario: Train from zero cloud workers
- **WHEN** a two-worker GPU workload is submitted within configured limits
- **THEN** two eligible AWS nodes join and provide GPU allocation without changing fixed Proxmox inventory

#### Scenario: Capacity or quota failure
- **WHEN** the selected region or zone cannot supply the required pair
- **THEN** the reason is observable and the workload does not silently use local capacity or another topology

### Requirement: Verified accelerator readiness
AWS GPU workers SHALL use a pinned compatible Talos image and GPU stack. Readiness evidence SHALL include allocated-device execution and a framework forward/backward pass; node registration alone SHALL NOT establish training readiness.

#### Scenario: Worker joined but device unverified
- **WHEN** a worker has joined the cluster
- **THEN** readiness is claimed only after an allocated GPU completes a framework forward/backward pass

### Requirement: Distributed runtime handoff
The platform SHALL expose a versioned runtime and scheduling contract supporting two GPU ranks on distinct AWS nodes. Acceptance SHALL verify rendezvous, all-reduce, worker identity, timeout behavior and the actual AWS-to-AWS traffic path without routing collectives through on-premises nodes.

#### Scenario: Two-node collective
- **WHEN** the acceptance workload executes
- **THEN** both AWS GPUs contribute to a verified collective and measured routing and throughput evidence is retained

#### Scenario: Missing second worker
- **WHEN** only one required worker becomes ready before the configured deadline
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
