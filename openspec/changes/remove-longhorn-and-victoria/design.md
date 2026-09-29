## Context

See proposal.md for motivation. The current state and constraints that shape the approach:

- `apps/argocd/platform/values.yaml` enables `local-path-provisioner` for `[dev]` and `longhorn` for `[prod]`. The local-path chart (0.0.38) is already the default StorageClass on dev, with `WaitForFirstConsumer` binding and `/opt/local-path-provisioner` as the default path for every node.
- `terraform/cluster/env/prod/k8s_nodes.json` has three `servers` (4 cores, 16/10/10 GB, 64 GB disk) and three `longhorn` nodes (`prod-longhorn1..3`, VM IDs 1221–1223, 2 cores, 6 GB, 300 GB disk), one of each on `pve`, `pve2`, and `pve3`. Every VM uses its host's `local-lvm`, which is SSD on `pve` and HDD on `pve2` and `pve3`. The hosts have enough memory for the combined VMs. `prod-server1` has the GPU passthrough.
- Talos already sets `allowSchedulingOnControlPlanes = true` and deletes the `exclude-from-external-load-balancers` label on `servers` nodes, so control-plane nodes already run pods and serve LoadBalancer traffic. No kubelet resource reservations are configured.
- `terraform/proxmox/locals.tf` treats `longhorn` like `worker` for machine type, and adds Longhorn-specific configuration: a `/var/lib/longhorn` kubelet bind mount and `iscsi_tcp`/`dm_crypt` modules for every node, plus the `node.longhorn.io/create-default-disk` label on `longhorn` nodes. `variables.tf` validates the role against `servers`, `worker`, and `longhorn`.
- `burst-policy` already rejects PVC-backed pods that are bound to or tolerate the AWS burst taint, independently of the storage driver. `awsNodeNamePrefix` notes that fixed nodes are named `<env>-<role><n>`.
- `cilium-network`'s prod values list the six fixed node names as L2 announcers.
- The Longhorn component owns the only prod ExternalSecret besides the tunnel token, which reads the three `LONGHORN_AWS_*` keys. No OpenTofu root reads or writes those keys.
- `apps/components/observability` wraps `victoria-metrics-k8s-stack` 0.86.0 for `[dev, prod]` in namespace `monitoring` at sync wave `1`. Its Grafana HTTPRoutes serve `grafana.phuchoang.sbs` and `grafana-dev.phuchoang.sbs` through the Cloudflare tunnel, whose public hostname routes are configured in Cloudflare, not in this repository. `applications.yaml` hardcodes `ignoreDifferences` for the Grafana admin Secret and Deployment checksum and for the Victoria operator's webhook Secret and `ValidatingWebhookConfiguration`, enabled by `ignoreDifferences: true` on this component only.
- Both environments are created from empty state after this change is pushed; no existing cluster, volume, or telemetry data is kept. Nothing needs to be pruned or cleaned up in a running cluster.

## Goals / Non-Goals

**Goals:**
- Dev and prod use the same storage component with the same values.
- No Longhorn artifact remains in Git, Talos machine configuration, or Doppler.
- No Victoria or Grafana artifact remains in Git, so freshly created clusters never install them and the next change adds its observability stack at a clean `observability` path and namespace.

**Non-Goals:**
- Any replacement observability, even temporarily. `add-clickstack-observability` adds it.
- Backups of local-path volumes. A later change adds application-level backups for the workloads that need them.
- Changing dev's inventory. It is already a single node that runs everything.
- Adding a separate disk for etcd or for local-path volumes.
- A dedicated disk or Talos user volume for any workload. ClickHouse placement is handled in `add-clickstack-observability`.
- Enforcing PVC capacity. local-path does not; workloads bound their own disk use.
- Upgrading running clusters in place. Removal is done only in Git; the clusters are created fresh afterwards, so there are no Argo CD prunes to watch and no leftover CRDs or namespaces to delete.

## Decisions

### Merge each storage VM into the control-plane VM on its host

Delete `prod-longhorn1..3` and give their resources to the `servers` VM on the same host:

| Node | Host | Disk type | CPU | Memory | Disk |
|---|---|---|---|---|---|
| `prod-server1` | pve | SSD | 6 | 22528 MB | 364 GB |
| `prod-server2` | pve2 | HDD | 6 | 16384 MB | 364 GB |
| `prod-server3` | pve3 | HDD | 4 | 16384 MB | 364 GB |

VM IDs 1211–1213, addresses, datastore, and `prod-server1`'s PCI devices stay. VM IDs 1221–1223 and addresses `10.69.12.21-23` are freed.

Each Proxmox host is already the real failure domain: losing `pve2` today takes out a control-plane member and a worker together, so merging does not widen what a host failure costs. It does remove three Talos nodes' worth of kubelet, containerd, Cilium, and DaemonSet overhead, and gives workloads such as ClickHouse larger nodes to pack onto. Three etcd members still tolerate one node being down for an upgrade or failure.

The `worker` role stays valid in `var.nodes`, so a dedicated worker can be added later without a code change. With no prod workers, `worker_nodes` is empty and only control-plane machine configurations are generated.

Alternatives considered:
- Keep separate worker VMs (renamed from `prod-longhorn1..3`). This isolates etcd from workload I/O, but costs a second VM per host with no gain in failure isolation, and leaves ClickHouse on a 2-core node.
- Consolidate to fewer than three nodes. This loses etcd quorum tolerance.

### Reserve resources for system services and the kubelet

Workloads now share every node with etcd and the API server. The common Talos patch sets `machine.kubelet.extraConfig` with `systemReserved` (250m CPU, 1 GiB memory) and `kubeReserved` (250m CPU, 512 MiB memory) on every node in both environments. Allocatable capacity shrinks by those amounts, so the scheduler cannot fill a node to the point where control-plane processes are starved of memory.

Alternative considered: rely on workload limits alone. That depends on every chart setting sane limits, and one that doesn't can OOM a control-plane node.

### Use the dev local-path configuration unchanged on prod

`local-path-provisioner` moves to `clusters: [dev, prod]` with no prod overlay. `DEFAULT_PATH_FOR_NON_LISTED_NODES` stays, so volumes go to `/opt/local-path-provisioner` on whichever fixed node the pod first schedules to. On prod that is one of the three servers, on the same Talos EPHEMERAL partition as etcd. AWS workers never receive a volume because `burst-policy` keeps PVC-backed pods off them, as it already does on dev.

Alternative considered: list only fixed Proxmox nodes in `nodePathMap` so provisioning fails on any other node. It duplicates the burst policy and would need editing on every inventory change.

### Remove Longhorn-only Talos configuration

- Drop the `/var/lib/longhorn` kubelet extra mount from `common_machine_patch`.
- Drop `iscsi_tcp` and `dm_crypt` from both the common and per-node kernel module lists. Nothing else in the platform uses iSCSI or dm-crypt; per-node NVIDIA modules stay. The `iscsi-tools` and `util-linux-tools` Talos extensions also leave both image schematics in `terraform/proxmox/image.tf`, since only Longhorn needed them.
- Drop the `create-default-disk` label; the `nodeLabels` merge keeps the GPU and control-plane entries.
- `var.nodes` validation accepts only `servers` and `worker`. `worker_nodes` selects `role == "worker"`.

These change the machine configuration of every prod and dev node. Both environments are created fresh with the new configuration, so no staged rollout is needed.

### Remove the observability component entirely

Delete `apps/components/observability/` and its `components` entry, rather than emptying it for reuse. The next change creates a new component at the same path with different charts, and deleting it now keeps that change's review free of Victoria diffs. The `ignoreDifferences` block in `applications.yaml` is deleted with it. The `if $app.ignoreDifferences` guard for the `RespectIgnoreDifferences` sync option stays, and the block guard becomes `with $app.ignoreDifferences`, rendering the component's own list from values, since other components may need it later.

Because both clusters are created fresh from the updated Git content, the Victoria CRDs and the `monitoring` namespace are simply never created; no prune or manual CRD cleanup is involved.

The Grafana public hostnames live in the Cloudflare tunnel's remote configuration. They are removed in Cloudflare; the tunnel component in this repository only carries the token and needs no change.

### Delete Doppler keys by hand

The three `LONGHORN_AWS_*` keys are operator-entered, and no OpenTofu root manages them, so an operator deletes them from the `prod` config after the Longhorn component is gone. The foundation root is not extended to manage individual secret keys.

## Risks / Trade-offs

- [No volume backups] → Accepted for now and stated as a non-goal. Losing a node's disk loses the volumes on it.
- [A node outage takes down every PVC-backed pod on it] → Accepted. Workloads that need availability must replicate at the application level (for example CNPG instances or Kafka brokers on different nodes).
- [local-path volumes share the Talos EPHEMERAL partition with etcd, images, and logs, without size limits] → Workloads with unbounded growth must bound themselves (retention, free-space limits). The 364 GB disks give headroom. A volume that fills the disk would also stop etcd on that node, but quorum survives the loss of one member.
- [etcd on `prod-server2` and `prod-server3` shares an HDD with pod volumes, and etcd is sensitive to fsync latency] → etcd already runs on those HDDs today; the new risk is write-heavy volumes landing there. Pin write-heavy stateful workloads (ClickHouse in the next change, and future databases) to `prod-server1` on SSD. If etcd reports slow fsync or leader changes, add a dedicated disk for etcd or for local-path in a later change.
- [Control-plane and workloads reboot together during Talos upgrades] → Upgrade one node at a time, as today; three etcd members tolerate one being down.
- [Existing Longhorn volumes and Victoria data are lost] → Accepted; both environments start from empty state.
- [No metrics, logs, traces, or alerts between this change and the next] → Accepted. The clusters can be created right after this change, or after `add-clickstack-observability` is also merged so they come up with the new stack.

## Migration Plan

1. Delete the files and update the configuration in Git, then push to `main` when ready to create the clusters.
2. Create dev and prod from empty state with the provisioning workflow. Their Argo CD instances install local-path and none of the removed components.
3. Confirm prod has three Ready control-plane nodes with the new sizes and reserved resources, and each cluster has exactly one default StorageClass, `local-path`, and no `longhorn-system` or `monitoring` namespace.
4. Delete `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, and `LONGHORN_AWS_SECRET_ACCESS_KEY` from the `prod` Doppler config, and the Grafana public hostnames from the Cloudflare tunnel.

Rollback is a revert followed by recreating the clusters; there is no data to restore.
