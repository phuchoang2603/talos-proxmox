# Doppler setup

Secrets live in Doppler project `talos-proxmox`. Cluster access is `TALOSCONFIG` / `KUBECONFIG`. GitHub Actions writes the Longhorn MinIO secret at bootstrap on prod.

Laptop CLI is `pkgs.doppler` via devenv. After `direnv allow`, run `doppler login` once.

## Layout

Configs: `dev`, `prod`, and `argocd` (same names as GitHub Environments). PR plans and main applies use the same per-environment Doppler config and `DOPPLER_TOKEN`; no separate `plan-*` configs are required. Plans can read Talos secrets from MinIO state, so restrict PR plan execution to reviewed, trusted branches.

| Secret | Use |
| --- | --- |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | MinIO S3 backend only, never the AWS provider |
| `PROXMOX_ENDPOINT`, `PROXMOX_USERNAME`, `PROXMOX_PASSWORD` | Mapped to `TF_VAR_proxmox_*` in CI |
| `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY` | `apps/bootstrap/bootstrap.sh` when any node has `role` `longhorn` (prod) |
| `CLOUDFLARE_TUNNEL_TOKEN` | `apps/bootstrap/bootstrap.sh`, provisioned as `cloudflare-tunnel/cloudflare-tunnel-token` on dev/prod |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | GitHub Actions Tailscale |
| `TALOSCONFIG`, `KUBECONFIG` | Laptop access (YAML); written after provision apply |
| `DOPPLER_READ_TOKEN` | **argocd config only** — project read token used by `bootstrap-argocd.sh` to fetch dev/prod kubeconfigs for Argo CD cluster registration |

`.doppler.yaml` pins the project and default config `dev`. Override with `DOPPLER_CONFIG=prod` / `DOPPLER_CONFIG=argocd` or `devenv.local.nix`.

CI needs a read/write service token as GitHub `DOPPLER_TOKEN` secret per Environment (OpenTofu apply and cluster credential writes). Never put an AWS IAM user access key into these MinIO backend variables. The `talos-proxmox-ci` IAM user key is stored in dev/prod as `AWS_PROVIDER_ACCESS_KEY_ID` / `AWS_PROVIDER_SECRET_ACCESS_KEY`; the separate `talos-proxmox-autoscaler` user key is stored there as `AWS_AUTOSCALER_ACCESS_KEY_ID` / `AWS_AUTOSCALER_SECRET_ACCESS_KEY`. Both users have project-scoped write policies recorded in `terraform/aws/iam/` (replace `ACCOUNT_ID` and `DEFAULT_VPC_ID` before policy updates). AWS Describe reads necessarily have account-wide scope; these keys must not be treated as fully isolated read credentials. Argocd needs neither key. The controller key must be delivered to Kubernetes as a Secret without committing it. Never reuse MinIO access keys for AWS resources.

## Local OpenTofu

```bash
export TF_VAR_env=dev
doppler run --only-secrets AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,PROXMOX_ENDPOINT,PROXMOX_USERNAME,PROXMOX_PASSWORD,AWS_PROVIDER_ACCESS_KEY_ID,AWS_PROVIDER_SECRET_ACCESS_KEY -- \
  bash -c 'cd terraform/cluster && bash ../../.github/scripts/opentofu-with-doppler.sh init -backend-config="key=talos-dev.tfstate" && bash ../../.github/scripts/opentofu-with-doppler.sh plan -var-file=env/dev/main.tfvars'
```
