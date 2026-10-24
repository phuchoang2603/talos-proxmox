# Tasks

## 1. Bounded GPU provisioning

- [x] 1.1 Extend `karpenter-nodes` values/templates for an optional independent GPU NodeClass/Pool while retaining the existing CPU identities; verify default and GPU-enabled Helm renders and finite GPU limits.
- [x] 1.2 Wire GPU AMI/bootstrap and pool settings through `terraform/platform/karpenter.tf` and environment secret references; verify OpenTofu validation/plan preserves ownership and exposes no bootstrap values in routine output.
- [x] 1.3 Pin a compatible GPU Talos schematic/AMI and GPU machine configuration, then extend the Karpenter IAM AMI allowlist; verify policy permits only approved CPU/GPU images and the environment's existing worker profile.
- [x] 1.4 Check regional G-family quota and two-instance availability in a selected us-east-1 zone, choose compatible single-GPU types and disk sizing, and set finite limits for one two-worker group; retain offering/quota/config evidence before enablement.
- [x] 1.5 Add GPU-only taint/labels, empty-only consolidation, bounded expiry/grace and pause controls; verify CPU pods cannot consume GPU capacity and paused GPU submissions cannot provision nodes.
- [x] 1.6 Configure budget alerts and verify existing destroy/cleanup logic covers both pools and permissionless worker roles; retain non-secret plan/notification configuration and cleanup checks.
- [x] 1.7 Remove obsolete free-plan assumptions in affected configuration/docs and minimally update AWS worker operational guidance for GPU limits and on-demand defaults; verify existing CPU pool behavior remains documented accurately.

## 2. Accelerator and distributed runtime readiness

- [x] 2.1 Extend pinned NVIDIA/DRA integration for compatible AWS GPU workers without changing local allocation semantics; verify scale-from-zero predicts GPU demand and an actual allocated GPU executes on each of two nodes.
- [x] 2.2 Add a pinned `aws-gpu-training` Trainer runtime using installed CRD-supported scheduling and timeout fields; verify runtime schema, two distinct hosts, selected zone and one GPU per rank without introducing an unconfigured scheduler.
- [x] 2.3 Validate the consumer-compatible framework image on AWS GPUs and the local RTX 5060 Ti; retain allocated-device forward/backward evidence.
- [ ] 2.4 Verify AWS-to-AWS pod routes, MTU, security/network policy and NCCL socket collective performance; repair demonstrated routing/encapsulation issues and retain evidence that collectives avoid on-premises transit.
- [ ] 2.5 Update only affected Kubeflow/GPU/AWS operation sections with runtime name, DRA allocation, local notebook exclusivity and measured network facts; verify instructions match installed versions and resolve touched contradictory MTU statements using measurements.

## 3. Regional object storage and workload access

- [ ] 3.1 Provision private encrypted versioned S3 staging storage and regional gateway endpoint through the AWS infrastructure owner; verify bucket public-access denial, selected route-table association and preservation on ordinary rollback.
- [ ] 3.2 Define dataset/checkpoint/output prefix and retention policies including active/pinned protection and abandoned multipart cleanup; verify plan and representative lifecycle cases cannot expire protected data.
- [ ] 3.3 Define separate transfer/reader/run-writer IAM roles and a trusted issuer identity limited to assuming them; verify reader writes, cross-run writes and dataset-prefix writes are denied while the worker role still has no S3 permissions.
- [ ] 3.4 Add the platform issuer step that mints per-run STS sessions scoped by session policy and delivers them as a namespace Secret; verify delivery, automatic expiry and early cut-off, with only the issuer's long-lived key in Doppler and no credentials in Git or routine logs.
- [ ] 3.5 Publish non-secret bucket/region/endpoint/prefix settings and access contract for fraud change `develop-gpu-models-and-train-on-aws`; verify an empty bucket is reported as storage-ready only, never dataset-ready.
- [ ] 3.6 Update affected AWS/Kubeflow operational storage sections for explicit copy, retention and credential responsibilities; verify no live Iceberg/catalog replication or untested RustFS interoperability is asserted.

## 4. Two-worker acceptance and lifecycle

- [x] 4.1 Add and run a bounded acceptance workload requesting two distinct on-demand AWS GPU nodes directly from zero; retain EC2/Node/rank/device identities, all-reduce correctness and a framework training-step result.
- [x] 4.2 Verify a missing second node reaches a visible deadline and cancellation removes all child workloads; retain cleanup evidence without local fallback.
- [ ] 4.3 Write a complete S3 checkpoint, terminate one worker and verify bounded whole-group recovery using replacement capacity; retain evidence that disposable scratch is not required and partial checkpoints are rejected.
- [ ] 4.4 Verify running bounded jobs resist voluntary consolidation and completed/canceled groups return GPU instances and Node objects to zero; verify local GPU notebooks, CPU bursting and controllers remain usable.
- [ ] 4.5 Keep Spot disabled and verify its configuration cannot be selected by the initial GPU runtime; document interruption-queue and recovery proof as prerequisites for a separately enabled Spot mode.
- [ ] 4.6 Deliver the verified runtime/pool, selected zone/types, resource/deadline bounds, GPU image stack, storage settings and private credential contract to the fraud change; verify names/selectors/prefixes match both proposals.
- [ ] 4.7 Run appropriate chart/OpenTofu checks and the two-worker integration suite; retain actual throughput, GPU utilization, transfer/cost and failure evidence, distinguishing proposed configuration from verified readiness.
