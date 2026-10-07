## 1. CI applies dev only on dispatch

- [x] 1.1 In `.github/workflows/terraform.yml`, replace the `[dev, prod]` push matrix with a single prod Provision job; verify `actionlint` passes and `manual.yml` still offers `dev` with `apply` and `destroy`
- [x] 1.2 Update `docs/architecture/terraform-ci.md` and other docs that describe dev as always on or applied on push; verify `rg` finds no remaining claim that pushes apply dev

## 2. Destroy dev

- [x] 2.1 Merge section 1; verify the push run applies prod only and succeeds
- [x] 2.2 Force-unlock the `talos-cluster-dev` HCP Terraform workspace; verify it reports unlocked
- [x] 2.3 Dispatch Manual Provision on `main` with `dev` and `destroy`; verify the run succeeds, VM 1111 no longer exists on `pve`, and both dev workspaces report no resources

## 3. Resize prod-server1

- [x] 3.1 In `terraform/cluster/env/prod/k8s_nodes.json`, set prod-server1's `cpu_cores` to 8 and `memory_mb` to 32768; merge only after 2.3 succeeds
- [x] 3.2 Verify the push run reboots prod-server1, the node reports 8 CPUs and about 32 GiB, it is Ready, and the ClickHouse, Grafana, and GPU workloads on it are running again

## 4. Remove the telemetry link between environments

- [x] 4.1 Make `otel-agent` prod-only: set `clusters: [prod]`, move prod's globals into `values.yaml`, delete `environments/` and the token ExternalSecret, and drop the agents' token header; verify `helm template` renders no token and the platform chart renders `otel-agent` only for prod
- [x] 4.2 In `observability`, remove the gateway's LoadBalancer, `bearertokenauth`, token env, and `otel-gateway-token` ExternalSecret; verify the gateway Service renders as ClusterIP
- [x] 4.3 Remove `OTEL_INGEST_TOKEN` from `terraform/foundation/doppler.tf` and update docs that describe dev telemetry, the LAN gateway, or the token
- [x] 4.4 Merge; verify Argo CD prunes the gateway LoadBalancer and both token Secrets, prod agents keep delivering telemetry, and `10.69.12.129` no longer answers
- [x] 4.5 Apply the foundation root locally; verify `OTEL_INGEST_TOKEN` is gone from both Doppler configs

## 5. Merge the agents into the observability chart

- [x] 5.1 Add `otel-agent` and `otel-cluster` aliases of `opentelemetry-collector` 0.174.0 to `observability`, move the agent values and globals into its `values.yaml`, delete `apps/components/otel-agent` and its Argo CD entry, and update the wave table; verify the merged chart renders the same 11 agent resources, differing only in release labels and alias-derived container names
- [x] 5.2 Merge; verify Argo CD removes the `otel-agent` Application, `observability` is Synced and Healthy with the agent DaemonSet and cluster collector running, and logs and metrics keep arriving
