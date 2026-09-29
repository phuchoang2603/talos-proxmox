## 1. Proxmox inventory and Talos configuration

- [x] 1.1 In `terraform/cluster/env/prod/k8s_nodes.json`, delete `prod-longhorn1..3` and set `prod-server1` to 6 cores, 22528 MB, 364 GB and `prod-server2`/`prod-server3` to 6 cores, 16384 MB, 364 GB, keeping VM IDs, hosts, addresses, datastore, and `prod-server1`'s PCI devices; verify `jq` shows exactly three `servers` nodes with those sizes
- [x] 1.2 In `terraform/proxmox/variables.tf`, restrict the role validation to `servers` and `worker` and update its error message; in `terraform/proxmox/vm/variables.tf`, update the `role` description; verify `tofu validate` in `terraform/cluster` passes
- [x] 1.3 In `terraform/proxmox/locals.tf`, select `worker_nodes` by `role == "worker"`, remove the `/var/lib/longhorn` kubelet extra mount, remove `iscsi_tcp` and `dm_crypt` from the common and per-node kernel module lists (keeping the NVIDIA modules), remove the `create-default-disk` label from `nodeLabels`, and drop the `iscsi-tools` and `util-linux-tools` extensions from both image schematics in `terraform/proxmox/image.tf`; verify `rg -i longhorn terraform/` returns nothing
- [x] 1.4 In the common Talos patch in `terraform/proxmox/locals.tf`, set `machine.kubelet.extraConfig` with `systemReserved` (250m CPU, 1Gi memory) and `kubeReserved` (250m CPU, 512Mi memory); verify the rendered machine configuration for `prod-server1` contains both reservations
- [x] 1.5 Verify `tofu validate` and `tofu fmt -check` pass for `terraform/cluster`, and that the rendered Talos machine configuration for `prod-server1` has no Longhorn mount, label, or iSCSI/dm-crypt module

## 2. Storage components

- [x] 2.1 In `apps/argocd/platform/values.yaml`, delete the `longhorn` entry and set `local-path-provisioner` to `clusters: [dev, prod]`; verify `helm template` of `apps/argocd/platform` renders a `local-path-provisioner` Application for prod and no `longhorn` Application
- [x] 2.2 Delete `apps/components/longhorn/`; verify `rg -i longhorn apps/` returns nothing after 2.3
- [x] 2.3 In `apps/components/cilium-network/environments/prod/values.yaml`, set `l2Announcement.nodes` to `prod-server1`, `prod-server2`, `prod-server3`; verify `helm template` renders the policy with only those three node names
- [x] 2.4 Verify the lint workflow's chart and OpenTofu checks pass locally for the changed charts and roots

## 3. Observability removal

- [x] 3.1 Delete `apps/components/observability/` and its `observability` entry in `apps/argocd/platform/values.yaml`; verify `helm template` of `apps/argocd/platform` renders no `observability` Application for either cluster
- [x] 3.2 Delete the hardcoded Grafana/Victoria `ignoreDifferences` block from `apps/argocd/platform/templates/applications.yaml`, keeping the `RespectIgnoreDifferences` option and rendering a component-supplied `ignoreDifferences` list instead; verify `helm template` renders no `ignoreDifferences` and `rg -i "grafana|victoria|monitoring" apps/` returns nothing
- [x] 3.3 Update the component and sync-wave tables in `docs/architecture/gitops.md` to drop observability; verify `rg -i "observability|grafana|victoria" docs/ README.md CONTRIBUTING.md` returns nothing

## 4. Storage documentation

- [x] 4.1 Update `README.md`, `docs/architecture/hybrid-aws-workers.md`, and `docs/operations/cluster-access.md` so both environments use local-path, prod has exactly one default StorageClass, `local-path`, and prod consists of three control-plane nodes that also run workloads, with `prod-server1` as the SSD-backed node for write-heavy volumes; verify none of them mention Longhorn or storage nodes
- [x] 4.2 Update `docs/architecture/gitops.md`: remove Longhorn from the sync-wave table, the pre-upgrade checker note, the ESO-owned Secret list, the refresh sentence, and the "Longhorn backups are meant to outlive it" sentence; verify `rg -i longhorn docs/architecture/gitops.md` returns nothing
- [x] 4.3 Update `docs/reference/secrets.md` to drop the `LONGHORN_AWS_*` rows, the MinIO note, and the `longhorn-minio-credentials` delivery row; update `CONTRIBUTING.md` to drop the Longhorn credentials, the Longhorn UI address row, and the `longhorn` role definition; verify `rg -i longhorn README.md CONTRIBUTING.md docs/` returns nothing

## 5. Rollout

- [ ] 5.1 Push to `main` when ready to create the clusters, and create dev and prod from empty state with the provisioning workflow; verify `kubectl get nodes` on prod lists only `prod-server1..3`, all Ready control-plane nodes, and that each node's allocatable CPU and memory are lower than its capacity by the reserved amounts
- [ ] 5.2 Verify on both clusters that `kubectl get storageclass` shows exactly one default class, `local-path`, that no `longhorn-system` or `monitoring` namespace exists, and that a test PVC with a pod binds on a Proxmox node
- [ ] 5.3 Remove the `grafana.phuchoang.sbs` and `grafana-dev.phuchoang.sbs` public hostnames from the Cloudflare tunnel configuration; verify neither hostname is listed for the tunnel in Cloudflare
- [x] 5.4 Delete `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, and `LONGHORN_AWS_SECRET_ACCESS_KEY` from the `prod` Doppler config; verify `doppler secrets --project talos-proxmox --config prod --only-names` lists none of them
