# AWS worker operations

[Documentation home](../../README.md) · [AWS architecture](../architecture/hybrid-aws-workers.md)

These operations apply to prod. Dev uses fixed Proxmox VMs and creates no AWS workers. First [select the cluster](cluster-access.md#select-an-environment), and enter `devenv shell`.

## Schedule a workload

Ordinary workloads may use any eligible node, including EBS-backed workloads. No stateless admission restriction or CPU worker taint exists. To require a Karpenter CPU worker, use this Pod selector and declare container CPU/memory requests:

```yaml
nodeSelector:
  karpenter.sh/nodepool: aws-cpu-burst
```

Spark job definitions are owned by the application repository; installing the Spark operator starts no jobs. Prod maintains one On-Demand `m6a.xlarge` CPU worker in `aws-workers` even when idle. The demand-driven `aws-cpu-burst` pool adds up to one `m6a.xlarge` Spot worker for pending workloads and consolidates idle/underutilized burst capacity after five minutes. Both pools share the `aws-cpu` EC2NodeClass and the same Karpenter controller. The baseline permits one extra worker during replacement. Select the burst pool explicitly only when a job must run on Spot.

## Observe scaling

```bash
kubectl get nodepool,ec2nodeclass
kubectl get nodeclaims -o wide
kubectl get nodes -l burst.talos.dev/compute=aws -o wide
kubectl -n kube-system logs deploy/karpenter --tail=200
```

One CPU worker is desired; a second is allowed temporarily during replacement. Check Pending pod events, instance capacity/quota, Karpenter permissions, the interruption queue, cloud provider IDs and Cilium readiness. Instance requests must fit allocatable capacity after Talos/system reservations and DaemonSets. Karpenter's predicted kubelet reservations must match Talos.

## GPU training pool

The `aws-gpu-training` pool shares the same controller and is disabled by default. Before enabling it, select a compatible pinned GPU image, allowed zones/types and finite limits. GPU jobs must select its label, tolerate its GPU taint and request a GPU. The pool is On-Demand only; enable Spot GPU training only after checkpoint/interruption recovery is verified. Idle GPU capacity returns to zero. The CPU baseline remains one worker.

## Object storage and Iceberg

Prod uses the generic bucket `platform-prod-<account>-<region>`, with purpose-scoped `OBJECT_<PURPOSE>_*` credentials for `artifacts/`, `lakehouse/`, `datasets/`, `runs/` and `backups/`. Worker instance roles grant no object access. Dev uses `platform-dev` on external MinIO; attach `terraform/cluster/env/dev/minio-artifacts-policy.json` to the shared Kubeflow/training identity for `artifacts/`, `datasets/` and `runs/`, and `minio-lakehouse-policy.json` to the separate lakehouse identity. Dev's `OBJECT_TRAINING_*` and `OBJECT_ARTIFACTS_*` values use the same access key and secret key.

Apache Polaris provides authenticated Iceberg REST at `http://iceberg-catalog.data.svc.cluster.local:8181/api/catalog`, with warehouse `lakehouse`. Table files and metadata JSON live in MinIO/S3; catalog state lives in single-instance CNPG. Clients use OAuth and their own scoped object credentials. Catalog availability does not prove an exported dataset is complete.

## Rotate the Karpenter key

With prod selected, initialize the cluster root and replace its key:

```bash
export TF_VAR_env=prod
export TF_WORKSPACE=talos-cluster-prod
tofu -chdir=terraform/cluster/prod init
tofu -chdir=terraform/cluster/prod apply \
  -var-file=../env/prod/main.tfvars \
  -replace=module.aws.aws_iam_access_key.karpenter
```

Then apply the platform root with `TF_WORKSPACE=talos-platform-prod` and `TF_VAR_target_revision` set to the full tested Git SHA. This updates the controller Secret and restarts Karpenter. No manual AWS key or Kubernetes Secret is needed.

## Destroy an environment

Use **Manual Provision** on main, selecting the environment and destroy. Select `purge_data` only when environment-owned EBS volumes/snapshots should also be deleted. Foundation S3 remains separately owned.

Cluster cleanup revokes Karpenter/CSI permissions, terminates workers, removes launch templates and the fixed control plane, and removes the network. It uses AWS APIs even when Kubernetes is unavailable. Platform state resets only after successful cleanup. A failed cleanup preserves state for retry. Normal destroy retains tagged persistent disks and snapshots.

For local destroy:

```bash
export TF_VAR_env=prod
export TF_WORKSPACE=talos-cluster-prod
tofu -chdir=terraform/cluster/prod destroy -var-file=../env/prod/main.tfvars
```

Set `PURGE_DATA=true` explicitly for a purge. After successful cluster destroy, select the matching platform workspace and remove its resources from state; do not attempt platform destroy against a vanished API. Never empty state after failed cloud cleanup.

## Inspect AWS resources in state

```bash
tofu -chdir=terraform/cluster/prod state list module.aws
```

Karpenter instances and launch templates are controller-owned and do not appear in OpenTofu state. See [control-plane recovery](../architecture/hybrid-aws-workers.md#control-plane-recovery) before replacing the fixed instance or its AMI.
