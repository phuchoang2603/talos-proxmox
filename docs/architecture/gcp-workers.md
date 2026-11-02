# GCP worker architecture

[Documentation home](../../README.md) · [GCP worker operations](../operations/gcp-workers.md)

Prod is an independent Talos cluster in project `talos-proxmox`, region `us-central1`, zone `us-central1-a`. Dev runs fixed Proxmox VMs only, with no cloud resources or node autoscaler.

## Capacity ownership

OpenTofu owns one fixed `e2-standard-4` control-plane/workload VM, its reserved public API address, the VPC/subnet, and GCE Managed Instance Groups (MIGs). Each VM has 4 vCPU and 16 GiB RAM. The CPU group starts at three On-Demand workers and is bounded at three; an optional Spot group starts at zero and is bounded at twelve. Cloud GPUs are not configured. Both environments keep Kubernetes `v1.37.2`.

Cluster Autoscaler `v1.37.0`, pinned by digest, runs only on the production control plane. It grows groups for pending pods and drains eligible underused nodes before removing them. OpenTofu ignores MIG `target_size` after creation so later applies do not reset autoscaled capacity. No GCE metrics-based autoscaler is attached to these groups. Minimum/maximum changes are delivered through the platform release's explicit `--nodes` arguments.

Talos GCP images are uploaded to a private image bucket by `terraform/gcp/foundation` and registered as Compute Engine images. Instance templates pass machine configuration through `user-data`. Separate `kube-env` metadata describes labels and 500m CPU/1536 MiB memory reservations for Autoscaler's scale-from-zero simulation, matching Talos system and kubelet reservations. Talos CCM initializes GCE provider IDs and Cilium handles pod networking. Templates use opportunistic updates; changing an image does not force-replace running workers.

AWS is available through the same foundation, cluster and platform roots with `cloud_provider="aws"`; GCP remains the default and creates no AWS resources; see [optional AWS operations](../operations/gcp-workers.md#optional-aws-infrastructure). Karpenter is removed.

Configuration: [`terraform/gcp/`](../../terraform/gcp/), [`terraform/platform/autoscaler.tf`](../../terraform/platform/autoscaler.tf), [`apps/components/cluster-autoscaler/`](../../apps/components/cluster-autoscaler/).

## Networking

The subnet is `10.81.0.0/24`. The control plane has private address `10.81.0.10` and a stable regional public address. Workers use the private API endpoint and same-VPC connectivity; production has no dependency on Proxmox or a cross-site KubeSpan mesh. Public management access to TCP 6443 and 50000 requires explicit operator/CI CIDRs of /24 or narrower. Workers have public egress addresses, avoiding a Cloud NAT dependency. The VPC MTU is 1460 and Cilium's VXLAN MTU is 1410.

## Identity and storage

GitHub Actions uses Workload Identity Federation for production provisioning. Dev needs no GCP identity. The CI identity can administer Compute Engine and the project IAM resources used by this stack; protect the production GitHub Environment and HCP state accordingly.

Autoscaler and CSI each have a separate, purpose-scoped service account and JSON key, handed through Doppler. Node service accounts have no project or application grants. Autoscaler permissions apply within the dedicated GCP project, and its configured groups bound its managed capacity. Do not share this project with unrelated autoscaled clusters. Organizational policies must permit the controller keys and GCS HMAC keys.

GCE PD CSI provides the sole default production StorageClass, `cloud-block` (backed by `pd-balanced` disks), with expansion, WaitForFirstConsumer and Retain. The controller runs on the fixed control plane; the node plugin runs on every node, including the control plane. A replacement can reattach a volume in the same zone after safe detachment. Driver manifests are based on upstream GCP PD CSI `v1.28.1`, adapted for Talos and without snapshot or data-cache controllers. Snapshot APIs are not installed by this chart.

Foundation owns private, versioned GCS buckets: one shared by training and the gateway, and separate ones for artifacts and substrate. Purpose-scoped HMAC identities use `https://storage.googleapis.com` with path-style addressing and signing region `auto`. S3 environment variable names remain for SDK compatibility; no AWS account is used. The GCS XML API is an S3 subset: consumers must validate their actual multipart, signing and object operations. S3 object-tag-based run expiry is not reproduced; run objects remain retained until explicit application cleanup, so active or pinned runs cannot expire accidentally. Bucket creation does not imply dataset completeness.

## Destroy and recovery

Deleting a MIG removes its managed instances even when Kubernetes is unavailable. The fixed control-plane boot disk and CSI volumes survive a normal destroy. Explicit `purge_data` deletes disks/snapshots labeled `platform-cluster=prod-talos` after instance teardown. Foundation buckets remain separately protected.

A retained control-plane disk is recovery material, not an automatic recovery mechanism. Stop autoscaling, preserve the existing Talos identity, and review a disk reattachment/etcd recovery plan before replacing the control plane. A fresh apply after destruction creates a new boot disk; it does not restore application data. The Terraform configuration targets fresh deployments.
