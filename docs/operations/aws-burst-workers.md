# AWS worker operations

[Documentation home](../../README.md) · [AWS architecture](../architecture/hybrid-aws-workers.md)

Both environments have independent AWS worker pools. Dev has fixed Proxmox VMs and a zero-baseline Spot pool; prod additionally maintains an On-Demand AWS baseline. First [select the cluster](cluster-access.md#select-an-environment), and enter `devenv shell`.

## Schedule a workload

Ordinary workloads may use any eligible node, including EBS-backed workloads. No stateless admission restriction or CPU worker taint exists. To require a Karpenter CPU worker, use this Pod selector and declare container CPU/memory requests:

```yaml
nodeSelector:
  karpenter.sh/nodepool: aws-cpu-burst
```

Spark job definitions are owned by the application repository; installing the Spark operator starts no jobs. Dev enables only the demand-driven CPU pool; its controller stays on the Proxmox control plane. Prod maintains one On-Demand `m6a.xlarge` CPU worker in `aws-workers` even when idle. The demand-driven `aws-cpu-burst` pool accepts `large` and `xlarge` instances from the C5–C7, M5–M7 and R5–R7 x86 families, including AMD variants. Prod permits up to four Spot workers within 16 vCPUs and 64 GiB RAM; dev retains its 4-vCPU/16-GiB bound. Idle/underutilized burst capacity consolidates after five minutes. Both pools share the `aws-cpu` EC2NodeClass and the same Karpenter controller. The baseline permits one extra worker during replacement. Select the burst pool explicitly only when a job must run on Spot.

## Observe scaling

```bash
kubectl get nodepool,ec2nodeclass
kubectl get nodeclaims -o wide
kubectl get nodes -l burst.talos.dev/compute=aws -o wide
kubectl -n kube-system logs deploy/karpenter --tail=200
```

Prod desires one baseline CPU worker; a second baseline worker is allowed temporarily during replacement. Spot workers scale independently within the burst limits. Check Pending pod events, instance capacity/quota, Karpenter permissions, the interruption queue, cloud provider IDs and Cilium readiness. Instance requests must fit allocatable capacity after Talos/system reservations and DaemonSets. Karpenter's predicted kubelet reservations must match Talos.

## GPU training pool

Prod enables `aws-gpu-training` under the same controller: Spot-only `g4dn.xlarge`, `g5.xlarge` or `g6.xlarge` in `us-east-1a`, bounded to one node, 4 vCPUs and 16 GiB RAM. It consolidates only when empty after five minutes and has no scheduled expiry. AWS must approve the G/VT Spot vCPU quota before jobs can provision capacity. Dev keeps this pool disabled.

Kubeflow runtime `aws-gpu-training` selects this pool, tolerates its GPU taint and allocates one GPU through an explicit NVIDIA DRA claim. The platform creates `ResourceClaimTemplate/aws-gpu-training` in `ml`; consumers using another training namespace must create the same template there. Training jobs need checkpoints in object storage and caller-managed retries after Spot interruption. Idle GPU capacity returns to zero. The CPU baseline remains one worker.

## Object storage and Iceberg

Prod uses the generic bucket `platform-prod-<account>-<region>`, with platform identities for training, artifacts and backups. Worker instance roles grant no object access. Dev uses `platform-dev` on external MinIO; attach `terraform/cluster/env/dev/minio-artifacts-policy.json` to the shared Kubeflow/training identity for `artifacts/`, `datasets/` and `runs/`. Dev's `OBJECT_TRAINING_*` and `OBJECT_ARTIFACTS_*` values use the same access key and secret key. The payment gateway repository owns its runtime integrations. Foundation owns the gateway prefix policy, provisions the unified prod storage identity and publishes `OBJECT_GATEWAY_*` credentials to gateway Doppler `prd`. Dev MinIO credentials remain externally provisioned using `terraform/cluster/env/dev/minio-gateway-policy.json`.

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

Then apply the platform root with `TF_WORKSPACE=talos-platform-prod` and `TF_VAR_target_revision` set to the selected full Git SHA. This updates the controller Secret and restarts Karpenter. No manual AWS key or Kubernetes Secret is needed.

## Destroy an environment

Prod deploys only through **Manual Provision** on main: select `prod` and `apply` to create or update the cluster. Pushes to main deploy dev only; trusted PRs still plan prod.

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
