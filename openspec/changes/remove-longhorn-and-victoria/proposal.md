## Why

Prod runs Longhorn on three dedicated 2-core, 6 GB storage VMs, one next to each control-plane VM on the same Proxmox host, while dev already runs on local-path and schedules workloads on its control plane. Longhorn's managers, instance managers, CSI sidecars, and iSCSI replication take memory and CPU from those small nodes, and its separate node role, Talos mounts, kernel modules, UI, and MinIO credentials make prod the special case. Without Longhorn, a separate storage VM per host only adds a second Talos node's overhead to the same failure domain. Both environments also run a VictoriaMetrics k8s stack with Grafana, which is being replaced by a ClickHouse-based stack in `add-clickstack-observability`. That change runs ClickHouse on local node disk, and it installs cleanly only if neither Longhorn nor the Victoria stack is still present. Both environments will be created from empty state after this change is pushed, so there is no data to migrate and nothing to clean up in running clusters.

## What Changes

- **BREAKING** Remove Longhorn from prod: the `longhorn` component, its Argo CD Application, its StorageClasses (`longhorn`, `longhorn-fast`), recurring snapshot and backup jobs, UI Gateway at `10.69.12.128`, and MinIO credential ExternalSecret.
- Run `local-path-provisioner` on both environments as the only default StorageClass. Prod uses the same configuration as dev.
- **BREAKING** Remove the three prod storage VMs (`prod-longhorn1..3`) and the `longhorn` node role. Fold their capacity into the control-plane VM on the same Proxmox host: `prod-server1` (pve) becomes 6 cores and 22 GB, and `prod-server2` (pve2) and `prod-server3` (pve3) become 6 cores and 16 GB. Each gets a 364 GB disk. Prod becomes three control-plane nodes that also run all workloads, as dev already does.
- Reserve CPU and memory for Talos system services and the kubelet on every node, so workloads cannot starve etcd or the API server.
- Remove Longhorn-only Talos configuration: the `/var/lib/longhorn` kubelet bind mount, the `iscsi_tcp` and `dm_crypt` kernel modules, the `iscsi-tools` and `util-linux-tools` image extensions, and the `node.longhorn.io/create-default-disk` node label.
- Announce Cilium L2 LoadBalancer addresses from the three prod servers only.
- Delete the `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, and `LONGHORN_AWS_SECRET_ACCESS_KEY` keys from the prod Doppler config.
- **BREAKING** Remove the `observability` component from both environments: the VictoriaMetrics k8s stack (Victoria operator and CRDs, vmagent, vmsingle, vmalert, Alertmanager, vlagent, vlsingle, vtsingle, node-exporter, kube-state-metrics), Grafana, the Grafana Gateway and Cloudflare hostnames, the `monitoring` namespace, and the Argo CD `ignoreDifferences` entries that exist only for Grafana and the Victoria operator.
- Until `add-clickstack-observability` lands, neither environment collects metrics, logs, or traces, and there is no alerting.
- Persistent volumes are not backed up after this change. Adding application-level backups is deferred to a later change.
- Update README, CONTRIBUTING, and architecture, operations, and secrets documentation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `hybrid-aws-burst-workers`: `local-path` becomes the sole default StorageClass in both environments; references to Longhorn storage nodes and replica disks are removed.
- `declarative-platform-bootstrap`: storage selection runs local-path in both environments instead of Longhorn in prod.
- `doppler-secret-delivery`: Longhorn backup credentials are no longer an operator-entered secret or an ESO-delivered application secret.

No existing capability specifies the observability stack or the split between control-plane and storage VMs, so removing them has no further spec delta. `add-clickstack-observability` introduces the `cluster-observability` capability.

## Impact

- **Argo CD:** `apps/argocd/platform/values.yaml` drops the `longhorn` and `observability` entries and enables `local-path-provisioner` for `[dev, prod]`. `apps/argocd/platform/templates/applications.yaml` drops the hardcoded Grafana and Victoria `ignoreDifferences` block. `apps/components/longhorn/` and `apps/components/observability/` are deleted.
- **Cilium:** `apps/components/cilium-network/environments/prod/values.yaml` announces from `prod-server1..3` only.
- **OpenTofu:** `terraform/cluster/env/prod/k8s_nodes.json` drops `prod-longhorn1..3` (VM IDs 1221–1223, addresses `10.69.12.21-23`) and resizes `prod-server1..3`. `terraform/proxmox/locals.tf` drops the Longhorn mount, kernel modules, and label, and adds kubelet resource reservations. `variables.tf` drops the `longhorn` role, and `terraform/proxmox/vm/variables.tf` updates the role description. The `worker` role remains available for future nodes.
- **Doppler:** an operator deletes the three `LONGHORN_AWS_*` keys from the `prod` config.
- **Cloudflare:** the tunnel's public hostnames `grafana.phuchoang.sbs` and `grafana-dev.phuchoang.sbs` are removed wherever they are configured outside this repository.
- **Docs:** `README.md`, `CONTRIBUTING.md`, `docs/architecture/gitops.md`, `docs/architecture/hybrid-aws-workers.md`, `docs/operations/cluster-access.md`, `docs/reference/secrets.md`.
- **Operations:** removal happens only in Git; dev and prod are then created from empty state, with no manual CRD or namespace cleanup. Pods with PVCs are pinned to the node where their volume was first created and stay Pending while that node is down. local-path does not enforce PVC sizes. `prod-server2` and `prod-server3` store etcd and local-path volumes on the same HDD-backed disk. Both environments run without observability until the next change.
