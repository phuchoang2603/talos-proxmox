# Doppler setup

Doppler project `talos-proxmox` is the single source for secrets. It has one config per environment, `dev` and `prod`, matching the GitHub Environments. OpenTofu writes every generated credential; operators enter only externally issued ones. Clusters read their own config through External Secrets Operator (ESO).

Start `devenv shell` from the repository root to use the local CLI tools, including Doppler and OpenTofu. Run `doppler login` once inside that shell.

## Layout

Operator-entered secrets, set directly in each config and never passed as OpenTofu variables:

| Secret | Use |
| --- | --- |
| `HCP_TERRAFORM_TOKEN` | HCP Terraform state for the cluster and platform roots; exported to OpenTofu as `TF_TOKEN_app_terraform_io` |
| `PROXMOX_ENDPOINT`, `PROXMOX_USERNAME`, `PROXMOX_PASSWORD` | Read by the cluster root through `data "doppler_secrets"` |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | GitHub Actions Tailscale |
| `CLOUDFLARE_TUNNEL_TOKEN` | `cloudflare-tunnel` ExternalSecret |
| `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY` | `longhorn` ExternalSecret for MinIO backups (prod only) |

Generated secrets, written by OpenTofu with `doppler_secret`:

| Secret | Written by | Use |
| --- | --- | --- |
| `ESO_DOPPLER_TOKEN` | `terraform/foundation/` | Read-only service token for this config; the platform root copies it into `external-secrets-auth/doppler-token` |
| `KUBECONFIG`, `TALOSCONFIG` | `terraform/cluster/` | Operator access and the platform root's providers |
| `AUTOSCALER_AWS_ACCESS_KEY_ID`, `AUTOSCALER_AWS_SECRET_ACCESS_KEY` | `terraform/cluster/` (`aws_iam_access_key`) | `cluster-autoscaler` ExternalSecret |

`.doppler.yaml` pins the project and default config `dev`. Override with `DOPPLER_CONFIG=prod` or `devenv.local.nix`.

## Tokens and credential separation

`terraform/foundation/` creates two service tokens per config: a read/write CI token, published as the matching GitHub Environment's `DOPPLER_TOKEN` secret, and a read-only ESO token, stored as `ESO_DOPPLER_TOKEN`. Each token can access only its own config. The ESO token is the only Doppler credential inside a cluster.

The HCP Terraform token, CI AWS credentials (short-lived, from the GitHub OIDC role), autoscaler AWS keys, CI Doppler tokens, and ESO tokens are all distinct. Never reuse one for another purpose. `LONGHORN_AWS_*` are MinIO credentials, not AWS IAM credentials.

The HCP Terraform free tier has no team permissions, so `HCP_TERRAFORM_TOKEN` is organization-wide: the same token (an organization owner's user token) goes in both configs, and anyone holding it can read every workspace's state.

## ESO consumption

Each cluster has one `ClusterSecretStore` named `doppler` (`apps/components/secret-stores/`). Components that need a secret declare an `ExternalSecret` that reads individual keys from it. ExternalSecrets refresh hourly, except the autoscaler's, which refreshes every 5 minutes. If Doppler is unreachable, existing Secrets stay in place and the ExternalSecrets report not ready.

`cloudflared` and Cluster Autoscaler read their Secrets only at startup. After changing `CLOUDFLARE_TUNNEL_TOKEN` or rotating the autoscaler key, wait for the Secret to refresh, then use Argo CD's **Restart** action on the Deployment.

## Local OpenTofu

State lives in HCP Terraform workspaces `talos-cluster-{dev,prod}` and `talos-platform-{dev,prod}`, created by `terraform/foundation/` with local execution: plans run on your machine and HCP Terraform only stores and locks state. The roots authenticate to Doppler with `DOPPLER_TOKEN` and to HCP Terraform with `tofu login` credentials. The cluster root also needs an AWS session for the account. Run them from the repository root:

```bash
tofu login app.terraform.io   # once; or export TF_TOKEN_app_terraform_io from HCP_TERRAFORM_TOKEN
export DOPPLER_TOKEN="$(doppler configure get token --plain)" TF_VAR_env=dev
export TF_WORKSPACE="talos-cluster-${TF_VAR_env}"
cd terraform/cluster
tofu init
tofu plan -var-file="env/${TF_VAR_env}/main.tfvars"
```

For the platform root, use `terraform/platform` with `TF_WORKSPACE="talos-platform-${TF_VAR_env}"` and no var file. Both roots refuse to plan if `TF_WORKSPACE` and `TF_VAR_env` name different environments.
