# AWS worker architecture

[Documentation home](../../README.md) · [AWS worker operations](../operations/aws-burst-workers.md)

Prod is an independent Talos cluster in AWS. Dev keeps its Proxmox control plane and fixed workers, with independent AWS burst capacity that scales from zero. The cluster roots share Talos identity/configuration/bootstrap modules, with separate identities and state.

## Topology

Terraform owns one On-Demand `m6a.xlarge` control-plane/workload node, a stable Elastic IP, a single-AZ VPC in `us-east-1a`, public subnet and S3 gateway endpoint. Karpenter is the sole worker provisioner; there is no ASG. Its controller stays on the fixed control plane.

The baseline CPU NodePool maintains one `m6a.xlarge` On-Demand worker. `limits.nodes: 2` permits one temporary replacement. It uses the pinned Karpenter 1.15.1 static-capacity feature, explicitly enabled. The baseline worker remains running when idle. A separate demand-driven Spot CPU NodePool accepts `large` and `xlarge` instances from the C5–C7, M5–M7 and R5–R7 x86 families, including AMD variants. Prod allows up to twelve Spot workers, bounded by 48 vCPUs and 192 GiB RAM, and consolidates idle/underutilized capacity after five minutes. Prod also enables a zero-baseline GPU Spot pool for one `g4dn.xlarge`, `g5.xlarge` or `g6.xlarge` in `us-east-1a`, bounded to 4 vCPUs and 16 GiB RAM; GPU Spot quota approval is required before it can launch.

The baseline provides 8 vCPUs and 32 GiB RAM before system reservations. Talos/Kubernetes reserve 500m CPU and 1536 MiB per node. Rendered platform requests are a lower bound; readiness also requires measuring runtime usage and placement.

Configuration: [`terraform/aws/`](../../terraform/aws/), [`terraform/platform/karpenter.tf`](../../terraform/platform/karpenter.tf), [`apps/components/karpenter-nodes/`](../../apps/components/karpenter-nodes/).

Dev runs its own Karpenter controller on the Proxmox control plane. Its separate `10.80.0.0/16` VPC, worker profile, credentials and interruption queue belong to `dev-talos`. Only the bounded Spot CPU pool is enabled; dev creates no AWS control plane or On-Demand baseline. The same AWS module uses the existing dev Talos identity instead of generating another cluster.

## Network path

Workers join their AWS control plane through same-VPC connectivity and local KubePrism. Cilium provides pod networking. Prod does not use cross-site KubeSpan or depend on dev. Intra-cluster traffic is limited by the node security group; public Talos/Kubernetes management access is restricted to operator CIDRs and the current CI egress /32. Dev management still uses Tailscale. Dev AWS workers join the Proxmox cluster over authenticated KubeSpan WireGuard on UDP 51820, using Talos discovery and KubePrism; Cilium uses a 1370-byte MTU for that cross-site path. Prod stays on its own VPC and 1450-byte MTU.

Public-subnet nodes use paid public IPv4 addresses for outbound connectivity; there is no NAT gateway or API load balancer. Cloudflare tunnels publish ClusterIP-backed application UIs. Prod does not render LAN IPAM or unbacked UI LoadBalancer Services.

## Spot replacement and storage

SQS and EventBridge deliver interruption events to Karpenter. Spot interruptions can stop workloads; loss of all Spot capacity leaves the fixed control plane and controller available to retry replacement. Replacement is bounded and stays within the selected AZ. Capacity is not guaranteed.

Workers register with the Karpenter unregistered startup taint; Talos CCM initializes their AWS provider IDs and Cilium initializes networking. There is no stateless taint or admission restriction. Ordinary PVC workloads can run on workers.

In prod, encrypted gp3 EBS is the sole default StorageClass, with WaitForFirstConsumer, Retain and expansion enabled. A replacement worker can reattach a volume within the same AZ after safe detachment. Single-instance CNPG and the single control plane are not HA. Dev instead uses node-bound local-path and external MinIO. Data on a Spot worker’s local disk is lost with that worker; local-path provides no cross-node recovery.

## Ownership and credentials

Foundation owns AWS account identities, scoped object consumers, the generic S3 bucket and the Spot service-linked role. Each cluster root owns its AWS networking, worker profile, interruption infrastructure, Karpenter credentials and API-independent cleanup. Prod additionally owns the fixed EC2 control plane and CSI credentials. The platform root owns Karpenter, its CRDs and NodePools. The platform root also owns Talos CCM. Argo CD owns EBS CSI and applications. Worker instance roles have no application storage permissions.

Destroy revokes controller permissions, terminates Karpenter-owned workers and removes launch templates through AWS APIs before deleting networking. Persistent volumes and snapshots are retained unless `purge_data`/`PURGE_DATA=true` is explicitly selected. Platform state resets only after cluster cleanup succeeds. Foundation is destroyed separately.

## Control-plane recovery

The fixed node's root EBS disk is retained on termination. An instance replacement creates a fresh root disk; it does not automatically reattach the retained etcd disk. Before any AMI replacement, take a Talos etcd snapshot and retain the current Talos identity/configuration. During recovery, stop the replacement and reattach the retained root disk as its boot device, or follow Talos disaster recovery using the snapshot. Never bootstrap an empty replacement as if it preserved the previous cluster. The Elastic IP preserves the endpoint, not etcd state. Verify recovery before treating this topology as operationally ready.
