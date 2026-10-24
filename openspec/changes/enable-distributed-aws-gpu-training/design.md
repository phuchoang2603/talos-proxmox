# Design

## Context

See proposal.md for motivation. AWS Talos workers already join the on-premises cluster over KubeSpan/KubePrism and Cilium. The `aws-burst` NodePool currently allows small CPU instances, both Spot and on-demand, with no default resource cap. Karpenter classes/pools are OpenTofu-owned in `terraform/platform/karpenter.tf`, not Argo-owned. The cluster infrastructure owns network, AMI and IAM; Karpenter's policy restricts launches to a pinned AMI. Worker instance roles have no permissions.

The platform pins Kubeflow Trainer 2.3.0, Katib 0.19.0 and a Kubernetes-native KFP development build. A torch runtime and JobSet are present; that does not prove multi-node readiness. Local GPU allocation is DRA-only: the NVIDIA device plugin is disabled and the extended GPU resource is mapped through DRA. The prod RTX 5060 Ti has 16 GB, and its prior smoke job does not establish framework training compatibility.

AWS workers cannot use PVCs. Existing 40 GiB disposable disks and CPU allocatable predictions were measured on CPU instance types. No S3 workload policy or Spot interruption queue currently exists.

## Goals / Non-Goals

Goals: expose one verified cloud training contract, retain existing CPU burst consumers and local GPU notebook use, and bound the cost/lifecycle of the first two-worker distributed group.

Non-goals: EKS, a second Kubeflow cluster, cloud persistent volumes, local automated training, GPU partitioning/MIG, a new Spark/Flink stack, model recipes, serving placement or production model promotion. Hub Catalog is optional discovery and is not the consumer's Hub Registry; its ephemeral database is not model lineage storage.

## Decisions

### Extend the existing pool chart and ownership

Keep the existing `aws-burst` CPU NodePool/Class identity stable. Extend `apps/components/karpenter-nodes` to render a separate opt-in `aws-gpu-training` NodePool/Class with independently supplied AMI, bootstrap, instance requirements, disk sizing, limits and disruption policy. OpenTofu's platform root continues to own both. Update destroy/cleanup handling for both pools without changing fixed inventory.

Use `burst.talos.dev/compute=aws` and `burst.talos.dev/workload=gpu-training`; preserve the stateless taint and add `burst.talos.dev/gpu-training=true:NoSchedule`. GPU jobs select this pool, tolerate both taints and request one GPU per pod. Required hostname anti-affinity places the two ranks on distinct machines; a selected single zone keeps peers near each other. Ordinary CPU workloads do not tolerate the GPU-specific taint.

Initial candidate types are single-GPU amd64 G5/G6 sizes with sufficient CPU/RAM and ephemeral space. Select a compatible type and us-east-1 AZ using real regional quota, offering and capacity checks before enabling the pool; there is no free-plan restriction. Prefer a small compatible allowlist, not unconstrained expensive GPU families. Initial capacity is on-demand only.

Set CPU/memory/GPU limits sufficient for exactly one two-worker group of the chosen types, with no room for two concurrent groups. Karpenter limits are eventually consistent, not a hard spending guarantee: also cap admitted run concurrency to one, enforce request/deadline bounds, expose a pool pause setting and configure AWS budget alerts. Record the chosen finite values in environment config before enablement.

### GPU image and scheduling readiness

Produce/pin a Talos AWS AMI schematic with the appropriate NVIDIA extensions and compatible kernel/driver/toolkit for the selected GPUs. Supply GPU-specific worker machine config privately through Doppler and update Karpenter's IAM AMI allowlist; changing chart AMI alone would be denied. Preserve IMDSv2 restrictions and permissionless worker roles.

Extend existing NVIDIA GPU/DRA configuration to cloud nodes only as required by the pinned supported versions. Verify discovery and Karpenter's predicted GPU capacity against actual DRA allocation; remove GPU startup taints only after the allocation path is ready. A pending extended GPU request must actually trigger scale-from-zero and become allocatable. Do not fabricate Node capacity to satisfy prediction or Jupyter UI selectors. Verify local DRA operation is unchanged.

The platform owns an `aws-gpu-training` Trainer runtime derived from the pinned torch runtime, not an unpinned upstream example. Validate Trainer 2.3.0 CRD scheduling patches and JobSet behavior; Context7 returns newer/proposed examples too. Use supported fields for node selection, tolerations, anti-affinity, two nodes, one GPU/rank and deadlines. No new scheduler is required initially: bounded rendezvous and cleanup handle partial capacity. Do not claim gang scheduling merely because JobSet is installed.

### Actual cloud-local collectives

Both training ranks stay in AWS; controllers stay on fixed nodes. Retain KubeSpan/KubePrism for control-plane access, existing Cilium pod networking and private API behavior. Explicitly inspect the AWS-to-AWS pod path: a single AZ does not prove packets avoid on-premises transit. Measure route, MTU, loss, bandwidth and NCCL all-reduce with two allocated GPUs.

Use a validated NCCL socket interface and compatible network policies/security-group rules confined to participating workers, without assuming RDMA/EFA. If traffic hairpins through on premises or pod MTU breaks transfers, fix peer routing/encapsulation before accepting the pool. Do not infer usable distributed performance from the current contradictory MTU documentation.

### Stateful progress in objects, stateless nodes

Provision a private, versioned, encrypted S3 bucket in the selected training region under the existing AWS infrastructure ownership. Prefixes are `datasets/<export-id>/` and `runs/<run-id>/{checkpoints,outputs}/`. Add an S3 gateway endpoint for selected subnet route tables to keep staging traffic in-region; measure residual control-plane and artifact-return egress.

Declare retention tiers: immutable pinned datasets/candidates are protected from automatic expiration; temporary run objects are tagged for bounded expiration only after run completion and checkpoint recovery requirements end. Abort abandoned multipart uploads. Preserve nonempty durable buckets on ordinary infrastructure rollback/destroy; destructive data removal is separately explicit. Bucket existence is not export readiness.

Do not grant S3 access to the EC2 worker role. Concurrency is capped at one run and there is a single consumer, so one dedicated IAM user is enough: its policy allows object and multipart operations only under `datasets/*` and `runs/*` of the staging bucket plus prefix-limited listing. Terraform in the foundation root owns the user and its access key, writes the key and non-secret bucket settings to Doppler, and an ExternalSecret delivers them to the training namespace. Karpenter or CI credentials are never used in pods. Per-run prefix isolation is not enforced by IAM; rotating the key (`tofu apply -replace=aws_iam_access_key.ml`) is the revocation path. Longer-term workload federation or per-run scoped sessions can replace the static key without changing storage behavior.

The AWS infrastructure root owns bucket/IAM; the platform delivers the Secret. The consumer chooses run IDs and prefixes under `runs/`.

Explicit source→S3 and S3→RustFS copy is the initial transport. RustFS directional asynchronous bucket replication is optional after testing the deployed version against AWS with versioning enabled on both ends. It never implies live lake/catalog replication or bypasses destination inventory/hash checks.

### Lifecycle and recovery

Initial GPU consolidation is empty-only, with bounded job durations shorter than declared expiry and sufficient termination grace. Avoid voluntary drift/replacement during an active bounded run; checkpoint-aware cancellation is the escape path. Workers remain disposable and may still fail unexpectedly.

The platform acceptance job runs a real two-GPU collective and forward/backward training step, writes a checkpoint to S3, loses/replaces a worker and demonstrates a bounded restart from complete state. Model-specific optimizer/RNG restoration is consumer-owned. Spot remains opt-in and disabled until interruption queue wiring and actual checkpoint-resume testing succeed; do not copy CPU Spot defaults into GPU training.

### Cross-repository handoff

Coordinate with fraud change `develop-gpu-models-and-train-on-aws`. Publish the runtime and pool name `aws-gpu-training`, selected region/zone, labels/taints, resource budgets, image/driver contract, GPU request mechanism, timeouts, S3 endpoint/bucket/prefix policy and private credential references. Consumer owns Notebook manifests/images, recipes, Katib/KFP jobs, export verification, checkpoint contents, RustFS import and Hub Registry lineage.

Local notebooks use fixed-node affinity and one DRA-mapped GPU resource. GPU allocation is exclusive: notebook contention queues. No local CPU training stack or inference reservation is introduced.

## Risks / Trade-offs

- GPU quotas/capacity fluctuate → check for a two-instance offering before enablement; remain visibly pending or fail, never silently use local capacity.
- DRA and Karpenter resource prediction may differ → prove scale-from-zero plus actual allocation before consumer handoff; adjust supported integration rather than fake capacity.
- Single-AZ socket NCCL may be slow → retain performance/cost evidence; initial success means correct distributed execution, not guaranteed speedup.
- Static workload credentials require lifecycle management → scope per run, private delivery, expiry/revocation and denied-access tests; federation is a later improvement.
- Empty-only consolidation costs more while a failed group remains → strict deadlines, cancellation cleanup and budget alerts.
- Two-worker limits are not an atomic spending cap → serialize groups and verify cleanup; report possible provisioning overshoot.

## Migration Plan

1. Add disabled GPU/storage configuration and render/plan checks while preserving current CPU output.
2. Select compatible AMI/type/AZ and quota, set finite pool limits, stage private bootstrap and scoped storage access.
3. Enable the GPU pool and run a two-worker acceptance job directly, including routing, S3 denial checks, worker-loss recovery, cancellation and return to zero.
4. Hand off only verified runtime/storage details; consumer then runs the model pipeline.
5. Roll back by pausing new GPU submissions, canceling jobs, deleting GPU NodeClaims/pool through its owner and revoking workload access. Preserve S3 data, existing CPU bursting, shared controllers and local GPU operation.
