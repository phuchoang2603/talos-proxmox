# Doppler setup

Secrets live in Doppler project `talos-proxmox`. Cluster access is `TALOSCONFIG` / `KUBECONFIG`. GitHub Actions writes the Longhorn MinIO secret at bootstrap on prod.

Start `devenv shell` from the repository root to use the local CLI tools, including Doppler and OpenTofu. Run `doppler login` once inside that shell.

## Layout

Configs: `dev`, `prod`, and `argocd` (same names as GitHub Environments). Only main applies use per-environment Doppler configs and `DOPPLER_TOKEN`; PRs run lint without state or secrets.

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

CI needs a read/write service token as GitHub `DOPPLER_TOKEN` secret per Environment (OpenTofu apply and cluster credential writes). `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in Doppler are **MinIO** S3 backend credentials, and `LONGHORN_AWS_*` also accesses MinIO; neither is an AWS IAM credential. Dev/prod CI gets short-lived AWS credentials from the GitHub OIDC role in `terraform/identity/`, not Doppler. Argocd does not need AWS access. The on-premises autoscaler needs a separate ASG-scoped identity before it can be enabled. Never reuse MinIO credentials for AWS resources.

## Local OpenTofu

```bash
export TF_VAR_env=dev
# Export TF_VAR_aws_provider_access_key_id and TF_VAR_aws_provider_secret_access_key
# from a separate local AWS session; set TF_VAR_aws_provider_session_token if temporary.
doppler run --only-secrets AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,PROXMOX_ENDPOINT,PROXMOX_USERNAME,PROXMOX_PASSWORD -- \
  bash -c 'cd terraform/cluster && bash ../../.github/scripts/opentofu-with-doppler.sh init -backend-config="key=talos-dev.tfstate" && bash ../../.github/scripts/opentofu-with-doppler.sh plan -var-file=env/dev/main.tfvars'
```
