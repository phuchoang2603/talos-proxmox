# AWS worker architecture

[Documentation home](../../README.md) · [AWS worker operations](../operations/aws-burst-workers.md)

Prod is an independent Talos cluster in AWS. Dev runs on Proxmox and creates no AWS capacity. The cluster roots share Talos identity/configuration/bootstrap modules, with separate identities and state.

## Topology

Terraform owns one On-Demand `m6a.xlarge` control-plane/workload node, a stable Elastic IP, a single-AZ VPC in `us-east-1a`, public subnet and S3 gateway endpoint. Karpenter is the sole worker provisioner; there is no ASG. Its controller stays on the fixed control plane.

The baseline CPU NodePool maintains one `m6a.xlarge` On-Demand worker. `limits.nodes: 2` permits one temporary replacement. It uses the pinned Karpenter 1.15.1 static-capacity feature, explicitly enabled. The baseline worker remains running when idle. A separate demand-driven Spot CPU NodePool adds up to one `m6a.xlarge` worker and consolidates idle/underutilized capacity after five minutes. The optional GPU NodePool is disabled until its image, instance types and finite limits are selected.

The baseline provides 8 vCPUs and 32 GiB RAM before system reservations. Talos/Kubernetes reserve 500m CPU and 1536 MiB per node. Rendered platform requests are a lower bound; readiness also requires measuring runtime usage and placement.

Configuration: [`terraform/aws/`](../../terraform/aws/), [`terraform/platform/karpenter.tf`](../../terraform/platform/karpenter.tf), [`apps/components/karpenter-nodes/`](../../apps/components/karpenter-nodes/).

## Network path

Workers join their AWS control plane through same-VPC connectivity and local KubePrism. Cilium provides pod networking. Prod does not use cross-site KubeSpan or depend on dev. Intra-cluster traffic is limited by the node security group; public Talos/Kubernetes management access is restricted to operator CIDRs and the current CI egress /32. Dev management still uses Tailscale.

Public-subnet nodes use paid public IPv4 addresses for outbound connectivity; there is no NAT gateway or API load balancer. Cloudflare tunnels publish ClusterIP-backed application UIs. Prod does not render LAN IPAM or unbacked UI LoadBalancer Services.

## Spot replacement and storage

SQS and EventBridge deliver interruption events to Karpenter. Spot interruptions can stop workloads; loss of all Spot capacity leaves the fixed control plane and controller available to retry replacement. Replacement is bounded and stays within the selected AZ. Capacity is not guaranteed.

Workers register with the Karpenter unregistered startup taint; Talos CCM initializes their AWS provider IDs and Cilium initializes networking. There is no stateless taint or admission restriction. Ordinary PVC workloads can run on workers.

Encrypted gp3 EBS is the sole default StorageClass, with WaitForFirstConsumer, Retain and expansion enabled. A replacement worker can reattach a volume within the same AZ after safe detachment. Single-instance CNPG and the single control plane are not HA. Dev instead uses local-path and external MinIO.

## Ownership and credentials

Foundation owns AWS account identities, scoped object consumers, the generic S3 bucket and the Spot service-linked role. The prod cluster root owns the fixed EC2 node, networking, worker profile, interruption infrastructure, Karpenter/CSI credentials and API-independent cleanup. The platform root owns Karpenter, its CRDs and NodePools. Argo CD owns EBS CSI, Talos CCM and applications. Worker instance roles have no application storage permissions.

Destroy revokes controller permissions, terminates Karpenter-owned workers and removes launch templates through AWS APIs before deleting networking. Persistent volumes and snapshots are retained unless `purge_data`/`PURGE_DATA=true` is explicitly selected. Platform state resets only after cluster cleanup succeeds. Foundation is destroyed separately.

## Control-plane recovery

The fixed node's root EBS disk is retained on termination. An instance replacement creates a fresh root disk; it does not automatically reattach the retained etcd disk. Before any AMI replacement, take a Talos etcd snapshot and retain the current Talos identity/configuration. During recovery, stop the replacement and reattach the retained root disk as its boot device, or follow Talos disaster recovery using the snapshot. Never bootstrap an empty replacement as if it preserved the previous cluster. The Elastic IP preserves the endpoint, not etcd state. Verify recovery before treating this topology as operationally ready.
