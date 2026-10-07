## Why

Dev runs around the clock but hosts no applications: `refurbished-marketplace` deploys only to prod, so dev's operators manage nothing. It holds 4 vCPUs and 16 GiB on `pve`, the same host as prod-server1, where ClickHouse is close to its memory ceiling. Microservice development fits a local cluster better. Dev is still useful for rehearsing risky platform changes, and the roots can already bring an environment up from fresh state and tear it down cleanly, so dev only needs to exist while it is in use.

## What Changes

- **BREAKING:** Pushes to `main` apply only prod. Dev is created, updated, and destroyed only through the Manual Provision workflow dispatched on `main`.
- Destroy the running dev cluster through that workflow. Its Doppler config, Argo CD definitions, and chart overlays stay, so a later dispatch rebuilds it unchanged.
- Resize prod-server1 from 6 vCPUs and 22 GiB to 8 vCPUs and 32 GiB, using the memory dev frees on `pve`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `declarative-platform-bootstrap`: CI applies prod on push and dev only on manual dispatch.
- `hybrid-aws-burst-workers`: the push-to-main scenario of the CI requirement covers prod only.

## Impact

- **CI:** `.github/workflows/terraform.yml` drops dev from the push matrix. `.github/workflows/manual.yml` is unchanged.
- **OpenTofu:** `terraform/cluster/env/prod/k8s_nodes.json` changes prod-server1's `cpu_cores` and `memory_mb`. Applying it reboots prod-server1 once.
- **Operations:** dev's HCP Terraform workspace is force-unlocked, then dev is destroyed. The local dev kubeconfig stops working until dev is rebuilt.
- **Docs:** `docs/architecture/terraform-ci.md` and other pages that describe dev as always on.
