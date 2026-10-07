## 1. CI applies dev only on dispatch

- [x] 1.1 In `.github/workflows/terraform.yml`, replace the `[dev, prod]` push matrix with a single prod Provision job; verify `actionlint` passes and `manual.yml` still offers `dev` with `apply` and `destroy`
- [x] 1.2 Update `docs/architecture/terraform-ci.md` and other docs that describe dev as always on or applied on push; verify `rg` finds no remaining claim that pushes apply dev

## 2. Destroy dev

- [ ] 2.1 Merge section 1; verify the push run applies prod only and succeeds
- [ ] 2.2 Force-unlock the `talos-cluster-dev` HCP Terraform workspace; verify it reports unlocked
- [ ] 2.3 Dispatch Manual Provision on `main` with `dev` and `destroy`; verify the run succeeds, VM 1111 no longer exists on `pve`, and both dev workspaces report no resources

## 3. Resize prod-server1

- [ ] 3.1 In `terraform/cluster/env/prod/k8s_nodes.json`, set prod-server1's `cpu_cores` to 8 and `memory_mb` to 32768; merge only after 2.3 succeeds
- [ ] 3.2 Verify the push run reboots prod-server1, the node reports 8 CPUs and about 32 GiB, it is Ready, and the ClickHouse, Grafana, and GPU workloads on it are running again
