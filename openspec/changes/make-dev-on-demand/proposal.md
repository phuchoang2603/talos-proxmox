## Why

Dev runs around the clock but hosts no applications: `refurbished-marketplace` deploys only to prod, so dev's operators manage nothing. It holds 4 vCPUs and 16 GiB on `pve`, the same host as prod-server1, where ClickHouse is close to its memory ceiling. Microservice development fits a local cluster better. Dev is still useful for rehearsing risky platform changes, and the roots can already bring an environment up from fresh state and tear it down cleanly, so dev only needs to exist while it is in use.

## What Changes

- **BREAKING:** Pushes to `main` apply only prod. Dev is created, updated, and destroyed only through the Manual Provision workflow dispatched on `main`.
- Destroy the running dev cluster through that workflow. Its Doppler config, Argo CD definitions, and chart overlays stay, so a later dispatch rebuilds it unchanged.
- Resize prod-server1 from 6 vCPUs and 22 GiB to 8 vCPUs and 32 GiB, using the memory dev frees on `pve`.
- **BREAKING:** Remove dev's only link to prod, its telemetry path. Dev no longer runs telemetry agents. Prod's OTLP gateway loses its LAN LoadBalancer (`10.69.12.129`) and bearer-token check, and the shared `OTEL_INGEST_TOKEN` is deleted from both Doppler configs.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `declarative-platform-bootstrap`: CI applies prod on push and dev only on manual dispatch; environments share no credentials or data.
- `hybrid-aws-burst-workers`: the push-to-main scenario of the CI requirement covers prod only.
- `cluster-observability`: telemetry is collected in prod only, and ingest is reachable only inside prod's cluster.
- `doppler-secret-delivery`: the telemetry ingest token is no longer generated.

## Impact

- **CI:** `.github/workflows/terraform.yml` drops dev from the push matrix. `.github/workflows/manual.yml` is unchanged.
- **OpenTofu:** `terraform/cluster/env/prod/k8s_nodes.json` changes prod-server1's `cpu_cores` and `memory_mb`. Applying it reboots prod-server1 once.
- **Operations:** dev's HCP Terraform workspace is force-unlocked, then dev is destroyed. The local dev kubeconfig stops working until dev is rebuilt.
- **Charts:** `otel-agent` targets prod only and drops its environment overlays and token ExternalSecret. `observability` drops the gateway's LoadBalancer, authenticator, and `otel-gateway-token` ExternalSecret.
- **Foundation:** `terraform/foundation/doppler.tf` stops generating `OTEL_INGEST_TOKEN`; an operator applies it locally after the charts stop reading it.
- **Docs:** `docs/architecture/terraform-ci.md`, `gitops.md`, `docs/reference/secrets.md`, `docs/operations/cluster-access.md`, and other pages that describe dev as always on or as a telemetry source.
