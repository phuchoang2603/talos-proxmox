# Verification evidence (2026-10-24, prod)

Verified readiness is limited to what is listed here; everything else in the change is proposed configuration.

## Network (task 2.4)

Two g6.xlarge workers, us-east-1b, pods on distinct nodes:

- Pod `eth0` MTU 1370; pod-to-pod route MTU 1320. A DF UDP payload of 1200 passed and 1300 or larger was refused, in both directions.
- TCP round trip p50 0.30 ms, p99 0.43 to 0.58 ms.
- NCCL socket all-reduce of 256 MiB: 2.14 s, 0.125 GB/s (1.00 Gbit/s) on both ranks. A single-stream TCP transfer between pods on the same nodes reached 1.68 Gbit/s.
- Traffic path: the transfer moved about 2.3 GB through `cilium_vxlan`, `kubespan` and `eth0` on both nodes. `talosctl get kubespanpeerstatuses` shows each worker's peer endpoint for the other is its private VPC address (`10.81.1.x:51820`); the three on-premises peers had exchanged under 10 MB in total. Collectives therefore do not transit on-premises.
- No routing fault was found, so nothing was repaired. The 1 to 1.7 Gbit/s ceiling comes from the WireGuard plus VXLAN encapsulation.
- Pods in `gpu-acceptance` cannot use `hostNetwork` (PodSecurity baseline), so node counters were read with `talosctl read /proc/net/dev`.

## Checkpoint and worker loss (task 4.3)

A PyTorch DDP job, run ID `accept-recovery`, checkpoints every 10 steps to `s3://<ML_BUCKET>/runs/accept-recovery/checkpoints/step-N/` (per-rank shard, then `manifest.json` with SHA-256 per rank written last):

- Steps 10 and 20 completed on both ranks; at 17:19:02Z the EC2 instance of rank 1 was terminated. The TrainJob reached `Failed` within about 14 s.
- A shard `step-999/rank-0.pt` without a manifest was seeded. Both ranks logged `reject step=999 reason=no_manifest`.
- The resubmitted TrainJob (same run ID) needed one replacement g6.xlarge. Capacity in us-east-1b was refused several times with `InsufficientInstanceCapacity` before it launched. Both ranks logged `RESUMED from step=20`, then completed step 60.
- Checkpoints needed no node-local scratch. The scoped IAM user could write objects and tag them `expire=true`.
- The runtime has no automatic group restart (`backoffLimit: 0`); recovery is resubmission by the caller.

## Lifecycle (task 4.4)

- Nodes stayed in place through every running job; the pool uses `WhenEmpty` consolidation only.
- After completion at 17:36Z, Karpenter disrupted both nodes as empty at 17:42Z. Drain took until 17:49:46Z. At 17:51Z there were no NodeClaims, no GPU Nodes and no running `aws-gpu-training` EC2 instances.
- `aws-burst` stayed Ready, local `prod-server1` kept its DRA slice, and the Trainer and JobSet controllers kept running. `nvidia-operator-validator` on the local node was already crash-looping before these tests.

## Spot (task 4.5)

`templates/gpu.yaml` fixes `karpenter.sh/capacity-type` to `on-demand`; rendering with `gpu.capacityTypes={spot}` and `nodePool.capacityTypes={spot}` leaves the GPU pool on-demand. The runtime selects only pool labels. No interruption queue exists, so queue provisioning and interruption-recovery proof are prerequisites for any Spot mode.

## Consumer contract (task 4.6)

- Runtime `ClusterTrainingRuntime/aws-gpu-training`, two ranks, one `nvidia.com/gpu` each, hostname anti-affinity, image `pytorch/pytorch:2.13.0-cuda13.0-cudnn9-runtime`.
- Pool `aws-gpu-training`: selector `burst.talos.dev/compute=aws`, `burst.talos.dev/workload=gpu-training`; tolerate `burst.talos.dev/stateless=true` and `burst.talos.dev/gpu-training=true`. `g6.xlarge` only, zones us-east-1a to 1d with both ranks required in the same zone, on-demand, limits cpu 8, memory 32Gi, 2 GPUs, `consolidateAfter` 5m, `expireAfter` 24h, 100Gi root volume.
- Node stack: Talos 1.13.9 GPU AMI `talos-proxmox-gpu-v1.13.9-6698d6f136c5`, NVIDIA open kernel modules and container toolkit 595.91.07.
- Deadlines: set `activeDeadlineSeconds` on every TrainJob; allow for capacity waits of 10 minutes or more.
- Storage: bucket, region and keys come from Secret `ml-s3` (`ML_BUCKET`, `AWS_DEFAULT_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) copied into the training namespace; prefixes `datasets/<export-id>/` and `runs/<run-id>/{checkpoints,outputs}/`. Mark finished runs with tag `expire=true`.
- The fraud change `develop-gpu-models-and-train-on-aws` is not present in any local repository, so its names, selectors and prefixes could not be compared and still need that check on its side.

## Suite (task 4.7)

`helm lint` of `karpenter-nodes` with prod values and `tofu validate` of `terraform/foundation` and `terraform/platform` pass. The acceptance manifests were run from a local checkout and are not kept in the repository.

Measured: all-reduce 1.00 Gbit/s; DDP and checkpoint steps on both ranks; S3 transfer was about 0.25 MiB per rank per checkpoint, so negligible. Cost was roughly 2 g6.xlarge for about 85 minutes, mostly waiting for capacity. GPU utilization was not sampled. Capacity failure (InsufficientInstanceCapacity in us-east-1b) was observed in three runs and is the main operational risk.
