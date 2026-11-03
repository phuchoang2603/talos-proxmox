# GCP worker operations

[Documentation home](../../README.md) · [GCP architecture](../architecture/gcp-workers.md)

Dev uses fixed Proxmox nodes only. Prod uses a fixed Talos control plane and Cluster Autoscaler-managed GCE workers. First [select the cluster](cluster-access.md#select-an-environment) and enter `devenv shell`.

## Schedule and observe workers

Declare CPU/memory requests. Ordinary workloads may run on any eligible node. Stateful applications select `talos.dev/capacity-type: on-demand`. To require interruptible CPU capacity, use:

```yaml
nodeSelector:
  talos.dev/nodepool: spot
```

The CPU group starts at three `e2-standard-4` workers and is bounded at three; the Spot group scales between zero and twelve. A full Spot group needs a project quota of at least 64 vCPU (`CPUS_ALL_REGIONS`) and 16 in-use external addresses in the region, because each worker has its own public IP. With the fixed GPU enabled, the full CPU/Spot/GPU deployment instead needs at least 68 vCPU and 17 external addresses. Disable Spot with `enable_spot=false` in the production inventory. CPU workers have no permanent taint. Keep checkpoints and caller-managed retries for Spot jobs; graceful shutdown cannot guarantee completion. Dev retains its local GPU and NVIDIA DRA runtime. Production inventory enables a dedicated GPU MIG with one on-demand `n1-standard-4` worker. It is registered with Cluster Autoscaler at bounds of one to one and remains enabled until `gcp_gpu_enabled=false`. The MIG keeps attempting to reach its desired size when GCP capacity is unavailable; check `gcloud compute instance-groups managed list-errors prod-talos-gpu --zone us-central1-a --project talos-proxmox` for creation failures. `gcp_gpu_zone` optionally selects another zone within the cluster region and defaults to `gcp_zone`. Zonal disks cannot attach across zones, so GPU jobs placed in another zone should use object storage or provision their PVCs in that zone. The worker uses the foundation-published `TALOS_GPU_IMAGE_ID`, NVIDIA system extensions and a 40 GiB `pd-balanced` boot disk. Deployment requires global GPU quota of at least one, regional T4 quota and sufficient SSD disk quota. GPU jobs select `talos.dev/nodepool: gpu`, tolerate `burst.talos.dev/gpu-training=true:NoSchedule`, and request a `gpu.nvidia.com` device through DRA. Production training defaults to one worker; validate allocated-device execution and a framework training step before relying on it.

```bash
kubectl get nodes -L talos.dev/nodepool,talos.dev/capacity-type
kubectl get pods -A --field-selector=status.phase=Pending
kubectl -n kube-system logs deploy/cluster-autoscaler --tail=200
kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml
gcloud compute instance-groups managed list --project=talos-proxmox
```

Check pending pod events, quota/capacity, GCE provider IDs, Talos CCM, Cilium and the CSI node plugin. Scale-down respects PodDisruptionBudgets, local storage protection and other drain constraints. The fixed control plane is outside autoscaled groups. Changing a MIG template affects future instances; existing workers need a deliberate drain/replacement for upgrades.

## Object storage

Production uses one object bucket, `talos-proxmox-prod-platform`, with the same top-level layout as dev `platform-dev`: `artifacts/`, `datasets/`, `lakehouse/`, `runs/` and `substrate/`. Kubeflow uses `artifacts/kubeflow/`; application artifacts retain `artifacts/langfuse/` and `artifacts/models/`; Substrate snapshots use `substrate/llm-agents/` or `substrate/llm/`. Each consumer keeps its own HMAC key. Artifact object access is limited to `artifacts/`, `datasets/` and `runs/`; Substrate object access is limited to `substrate/`. GCS bucket listing can expose object names outside those prefixes. `OBJECT_STORAGE_BUCKET`, `OBJECT_ARTIFACTS_BUCKET` and `OBJECT_SUBSTRATE_BUCKET` all name the shared bucket. Talos images remain in their separate image bucket. The gateway's application repository holds its own copy of the gateway credentials, bucket and endpoint in its Doppler project; platform changes alone do not migrate its runtime configuration or restore deleted AWS data.

Use GCP endpoint `https://storage.googleapis.com`, signing region `auto` and path-style addressing. Do not use S3 object tagging or assume every S3 API is available. Run objects have no automatic expiry; keep explicit completed-run cleanup in the owning application. Dev retains MinIO and its existing externally provisioned credentials and policies. The payment gateway continues to own Polaris and its PostgreSQL catalog; external data and artifacts must be restored from available backups before jobs can use them.

## Rotate controller keys

With production selected, replace the relevant generated key and review the plan before applying (GCP example):

```bash
export TF_VAR_env=prod
export TF_WORKSPACE=talos-cluster-prod
tofu -chdir=terraform/cluster/prod init
tofu -chdir=terraform/cluster/prod apply -var-file=../env/prod/main.tfvars \
  '-replace=module.gcp[0].google_service_account_key.controller["autoscaler"]'
```

Apply platform next with `TF_WORKSPACE=talos-platform-prod` and the selected full Git SHA. It updates Autoscaler's Secret and restarts the Deployment through its credential checksum. For GCP CSI, replace the `"pd-csi"` key instead, wait for `ExternalSecret/gce-pd-csi-gcp` to refresh in `operators`, then restart `deployment/csi-gce-pd-controller`. For AWS, replace `module.aws[0].aws_iam_access_key.autoscaler` or `module.aws[0].aws_iam_access_key.ebs`, apply platform, wait for CSI credentials to refresh and restart its controller. Key rotation can interrupt scaling/storage operations until the new credentials are delivered.

## Optional AWS infrastructure

The same three deployment layers support AWS: `terraform/foundation` calls `terraform/aws/foundation`, `terraform/cluster/prod` calls `terraform/aws`, and `terraform/platform` configures Cluster Autoscaler and Argo CD for the selected cloud. There is no additional AWS deployment root or state. GCP is selected by default, creating no AWS resources and requiring no AWS credentials.

For a fresh AWS deployment, set `cloud_provider="aws"` in the private foundation variable file and provide `aws_talos_ami_id`, a current AMI matching `talos_version` in `aws_region` (default `us-east-1`). Authenticate locally to AWS before applying foundation. It creates production-only GitHub OIDC, separate versioned S3 buckets and bucket-scoped identities, then publishes the same Doppler object-storage contract and provider selection used by GCP. Review the budget recipient and GitHub trust before applying. Optional GPU image imports remain available with `enable_aws_gpu_images=true`; no cloud GPU worker group is configured.

Production uses one fixed `m6a.xlarge` control-plane/workload VM and three initial `m6a.xlarge` CPU workers in `us-east-1a`: the same 16 vCPU/64 GiB baseline as GCP. CPU ASG bounds are 3–4, optional Spot bounds are 0–4, and Cluster Autoscaler owns desired capacity after creation. Launch templates and ASG tags share the GCP `talos.dev/nodepool` and `talos.dev/capacity-type` labels. Template changes affect future workers; drain and replace existing workers deliberately.

The existing provisioning workflow selects AWS OIDC automatically from foundation's GitHub environment variables. Adjust `aws_region`, `aws_zone` and `aws_machine_type` in the production inventory when changing AWS defaults. Platform reads the selected provider from Doppler, installs EBS CSI for AWS or GCE PD CSI for GCP, and exposes one default `cloud-block` StorageClass with Retain, expansion and WaitForFirstConsumer. Workload storage settings use foundation's selected buckets, endpoint and signing region. Karpenter is not installed.

Provider selection is for fresh deployments; changing it on an existing stack requests infrastructure replacement and does not transfer disks, objects, applications or cluster identity. Foundation buckets remain protected by `prevent_destroy`.

## Deploy or destroy

Authenticate locally using `gcloud auth login` and `gcloud auth application-default login`; select project `talos-proxmox`. The GCP project must already exist with billing enabled. Apply foundation locally with the private operator variable file to enable APIs, create images/storage/identities and publish GitHub federation variables. Set production Doppler `CLOUD_MANAGEMENT_CIDRS` to a JSON array of stable operator CIDRs. CI adds its own egress /32.

Use **Manual Provision** on main, selecting `prod` and `apply`. Pushes deploy dev only; trusted PRs plan prod. Verify node registration, a pending-pod scale-out, Spot scale-from-zero, idle scale-down and a PVC write/remount before treating the deployment as operational. Configuration validation is not evidence of those live checks.

Use the same workflow with `destroy` for teardown. Normal destroy retains persistent disks and snapshots. Select `purge_data` only to delete environment-owned labeled disks/snapshots; foundation object buckets remain. Platform state resets only after successful cluster teardown. For local destruction, set `PURGE_DATA=true` only when purging is intended. Never empty platform state after failed cloud cleanup.

Trial credits are temporary, and this preserved production capacity is not an always-free deployment. Review quota, instance/IP/disk charges and the credit expiry before applying. Optional foundation budget alerts require `gcp_billing_account`; they notify billing administrators and do not impose a spending cap.
