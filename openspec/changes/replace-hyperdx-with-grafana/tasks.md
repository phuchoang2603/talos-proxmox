## 1. Credentials

- [x] 1.1 In `terraform/foundation/doppler.tf`, remove `HYPERDX_MONGODB_PASSWORD` and `random_uuid.hyperdx_api_key`, and add `GRAFANA_ADMIN_PASSWORD` to the prod-only `random_password.observability` set; verify `tofu validate` passes and a plan shows one new password and secret and two deleted secrets, with sensitive values
- [x] 1.2 Apply the foundation root locally; verify `doppler secrets --project talos-proxmox --config prod --only-names` lists `GRAFANA_ADMIN_PASSWORD` and neither HyperDX key

## 2. Remove HyperDX from the observability chart

- [x] 2.1 Remove the `clickstack` dependency from `Chart.yaml`, delete `charts/clickstack-3.4.0.tgz`, `templates/mongodb.yaml`, and `files/sources.json`, and drop the `clickstack`, `store.mongodb`, and `global.hyperdxAddress` values; verify `helm template` renders no HyperDX Deployment, `MongoDBCommunity`, or MCK RBAC
- [x] 2.2 Remove the `hyperdx` and `hyperdx-mongodb-password` ExternalSecrets; verify `helm template` renders only `clickhouse-credentials` and `otel-gateway-token` among the existing ExternalSecrets

## 3. Add Grafana

- [x] 3.1 Add the `grafana` chart 13.2.7 from `https://grafana-community.github.io/helm-charts` as a dependency, run `helm dependency build`, and commit the archive and `Chart.lock`; verify `helm template` succeeds and update the chart description
- [x] 3.2 Add an ExternalSecret `grafana-admin` (user `admin`, password from `GRAFANA_ADMIN_PASSWORD`) and point `admin.existingSecret` at it; verify the rendered Grafana Deployment reads both keys from that Secret and no manifest contains a credential value
- [x] 3.3 Configure Grafana as stateless: `persistence.enabled: false`, one replica, requests 100m/256Mi, limit 512Mi, `testFramework.enabled: false`, and `grafana.ini` with `users.allow_sign_up = false`, anonymous access off, update checks and reporting off, and `server.root_url = http://10.69.12.128`; verify the rendered pod has no PVC and the rendered `grafana.ini` contains those settings
- [x] 3.4 Set `plugins` to `grafana-clickhouse-datasource` pinned to 4.22.1; verify the rendered Deployment installs exactly that plugin version
- [x] 3.5 Provision the ClickHouse data source (UID `clickhouse`, default, not editable, native protocol to `clickstack-clickhouse-headless.observability.svc:9000`, user `app`, password `$__env{CLICKHOUSE_APP_PASSWORD}` from `clickhouse-credentials` through `envValueFrom`, OTel-enabled logs on `otel_logs` and traces on `otel_traces` with links shown); verify the rendered provisioning file holds no literal password and the env var references the Secret
- [x] 3.6 Replace `templates/ui-service.yaml` with a `grafana-ui` LoadBalancer Service at `10.69.12.128` port 80 targeting Grafana's port 3000 and selecting only the Grafana pods; verify `helm template` renders one LoadBalancer Service at that IP with a single port

## 4. Dashboards

- [x] 4.1 Copy all eight dashboards from `grafana/clickhouse-datasource` tag `v4.22.1` `src/dashboards/` into `apps/components/observability/dashboards/`, replacing each dashboard's import placeholders with `clickhouse`; verify each file is valid JSON and no import placeholder remains
- [x] 4.2 Render a `grafana-dashboards` ConfigMap from `dashboards/*.json`, add a file dashboard provider for a `ClickHouse` folder with `allowUiUpdates: false`, map it with `dashboardsConfigMaps`, and keep the sidecar disabled; verify `helm template` renders the ConfigMap with eight keys under 1 MiB and the provider config
- [x] 4.3 Record the plugin tag the dashboards were copied from next to the plugin version in `values.yaml`; verify both reference 4.22.1

## 5. Bound UI queries

- [x] 5.1 In `templates/clickhouse.yaml`, add `profiles.grafana` to `extraUsersConfig` with `max_memory_usage` 536870912 and `max_execution_time` 60, switch the `app` user to profile `grafana`, and add only `READ ON REMOTE` to its grants for the monitoring dashboard's `clusterAllReplicas` panels; verify `helm template` renders the profile and the `ClickHouseCluster` passes `kubectl apply --dry-run=server` on prod

## 6. Documentation

- [x] 6.1 Update `docs/architecture/gitops.md`: replace HyperDX with Grafana in the ownership table, the sync-wave table, and the UI exposure paragraph; verify no HyperDX or ClickStack-UI reference remains there
- [x] 6.2 Update `docs/operations/cluster-access.md`: Grafana at `http://10.69.12.128`, admin login with `doppler secrets get GRAFANA_ADMIN_PASSWORD --plain --project talos-proxmox --config prod`, the stateless behavior and editing dashboards in Git, and filtering by `deployment.environment`; remove the first-signup step; verify the commands and address match the chart
- [x] 6.3 Update `docs/reference/secrets.md`: replace the two HyperDX keys with `GRAFANA_ADMIN_PASSWORD`, change the `CLICKHOUSE_APP_PASSWORD` consumer to Grafana, update the delivered Secrets row to `grafana-admin`, and change the rotation note to restart Grafana; verify the tables match design.md
- [x] 6.4 Replace the ClickStack mention in `docs/operations/kubeflow.md` with the observability stack; verify `rg -i 'hyperdx|clickstack' docs` returns only intended references to the ClickHouse cluster name

## 7. Validation

- [x] 7.1 Run the lint workflow's chart and OpenTofu checks locally in `devenv shell`; verify they pass
- [ ] 7.2 After merge, verify on prod that Argo CD pruned the HyperDX Deployment, `hyperdx-mongodb`, and its RBAC, that the MongoDB operator is still running in `operators` on both clusters, and that the ClickHouse pod restarted and is ready
- [ ] 7.3 Verify Grafana at `http://10.69.12.128`: the admin login works, sign-up and anonymous access are refused, the ClickHouse data source tests successfully, and Explore shows dev and prod logs filtered by `deployment.environment` and a trace that links to its logs
- [ ] 7.4 Open all eight provisioned dashboards and verify every panel loads data or an empty result without a data source error
- [ ] 7.5 Verify the query limits: as user `app`, a query exceeding 512 MiB fails with a memory-limit error while `otel_logs` inserts continue, and an `INSERT` is refused
- [ ] 7.6 Delete the Grafana pod and verify the replacement shows the same data source and dashboards and the admin login still works
- [ ] 7.7 Delete the orphaned `hyperdx-mongodb` PVCs in `observability` on prod; verify `kubectl get pvc -n observability` lists only the ClickHouse and Keeper claims
