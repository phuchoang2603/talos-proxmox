# Doppler setup

Secrets live in Doppler project `talos-proxmox`. Cluster access is `TALOSCONFIG` / `KUBECONFIG`. GitHub Actions writes the Longhorn MinIO secret at bootstrap; nothing in the cluster talks to Doppler.

Laptop CLI is `pkgs.doppler` via devenv. After `direnv allow`, run `doppler login` once.

## Layout

Configs: `dev`, `prod`, and `gpu` (same names as git env folders and GitHub Environments). Shared keys are in all three.

| Secret | Use |
| --- | --- |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Terraform S3/MinIO backend |
| `PROXMOX_ENDPOINT`, `PROXMOX_USERNAME`, `PROXMOX_PASSWORD` | Mapped to `TF_VAR_proxmox_*` in CI |
| `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY` | `apps/bootstrap.sh` |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | GitHub Actions Tailscale |
| `TALOSCONFIG`, `KUBECONFIG` | Laptop access (YAML); written after provision apply |

`.doppler.yaml` pins the project and default config `dev`. Override with `DOPPLER_CONFIG=prod` / `DOPPLER_CONFIG=gpu` or `devenv.local.nix`.

CI needs a read/write service token as GitHub secret `DOPPLER_TOKEN` (repository or Environment).

## Local Terraform

```bash
doppler run --only-secrets AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,PROXMOX_ENDPOINT,PROXMOX_USERNAME,PROXMOX_PASSWORD -- \
  bash -c 'export TF_VAR_proxmox_endpoint="$PROXMOX_ENDPOINT" TF_VAR_proxmox_username="$PROXMOX_USERNAME" TF_VAR_proxmox_password="$PROXMOX_PASSWORD"
    cd terraform-provision && terraform init --backend-config="key=talos-dev.tfstate" && terraform plan -var-file=env/dev/main.tfvars'
```
