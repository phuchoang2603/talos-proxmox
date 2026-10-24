# Proposal

## Why

The existing AWS Talos burst pool supports CPU stateless jobs but cannot provide GPU workers for fraud-model training. Extend that capacity while preserving the existing cluster, local GPU notebook use and fixed-node storage ownership.

## What Changes

- Add an opt-in, bounded AWS GPU NodePool and GPU-capable Talos AMI/bootstrap path alongside the existing CPU pool; remove obsolete AWS free-plan assumptions.
- Start with single-GPU on-demand workers, one per job and up to two jobs at once, across the us-east-1 zones with scale-to-zero cleanup. Jobs are independent; multi-node collectives were measured once but are not a supported contract.
- Expose a pinned Trainer runtime/scheduling contract and validate GPU allocation, single-node execution and recovery without involving the local GPU in training.
- Provide a regional S3 staging/checkpoint bucket and scoped workload access independent of permissionless worker instance roles and Karpenter credentials.
- Validate the existing local DRA GPU path for notebooks without splitting the local platform into CPU/GPU training stacks.

## Capabilities

### New Capabilities

- `distributed-gpu-training`: Single-GPU cloud capacity, runtime readiness, bounded lifecycle and consumer handoff.
- `ml-object-staging`: Scoped S3 staging/checkpoint infrastructure for immutable ML exports.

### Modified Capabilities

None. GPU pools extend the existing optional stateless burst contract; worker instance roles remain permissionless and PVCs remain on fixed nodes.

## Impact

Extend `apps/components/karpenter-nodes`, `terraform/platform/karpenter.tf`, AWS AMI/IAM/storage provisioning and pinned Kubeflow/GPU integration where required. Preserve OpenTofu ownership of Karpenter resources and the existing CPU pool. Consumer change `develop-gpu-models-and-train-on-aws` owns notebook images, model recipes, transfer validation, pipelines and candidate Registry entries. No EKS cluster, persistent cloud volumes, Spark/Flink orchestration changes, live lake replication or serving migration.
