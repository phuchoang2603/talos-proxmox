# HashiCorp Vault Setup

This guide covers storing secrets and applying `terraform-admin` so GitHub Actions can use Vault.

## Prerequisites

- HashiCorp Vault instance
- Vault CLI
- Appropriate Vault permissions

## Step 1: Store Secrets in Vault

```bash
export VAULT_ADDR="https://your-vault-address"
export VAULT_TOKEN="your-vault-token"

vault kv put kv/shared/minio access_key="..." secret_key="..."
vault kv put kv/shared/proxmox endpoint="..." username="..." password="..."
vault kv put kv/shared/cloudflare api_token="..." domain="..." email="..."
```

Cluster IPs (`vip`, `lb_range`, `ingress`) live in git: `terraform-provision/env/{dev,prod}/network.json`. Do not store them in Vault.

There is no RKE2 join token. Talos machine secrets live in the provision Terraform state (`talos-${ENV}.tfstate`). After each provision apply, Terraform also writes **`kv/{env}/talos`** (`talosconfig`, `kubeconfig`) so laptops can `vault kv get` without Terraform. That path is admin-only; GitHub Actions JWT may create, update, and delete it.

## Step 2: Configure Vault Users

```bash
cd terraform-admin
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your users. Roles must be `admins`, `developers`, or `viewers` per environment.

## Step 3: Deploy Vault Admin Resources

`terraform-admin` uses MinIO key `admin.tfstate` — the same object as kubernetes-proxmox. Prefer **migrating that state** into this repo’s apply, then changing JWT `github_repository` to `talos-proxmox` (already set in `main.tf`). A second independent apply against empty state will fail because the JWT mount already exists.

```bash
cd terraform-admin
export TF_VAR_vault_addr="$VAULT_ADDR"
export AWS_ACCESS_KEY_ID=$(vault kv get -field=access_key kv/shared/minio)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -field=secret_key kv/shared/minio)

terraform init
terraform apply
```

This configures:

- JWT auth for GitHub Actions, bound to the immutable GitHub OIDC `sub` for this repo (`repo:phuchoang2603@91061595/talos-proxmox@1351657631:...`). Repos created after 2026-07-15 include owner and repo IDs in `sub`.
- Per-environment Vault policies and identity groups

After this apply, kubernetes-proxmox GitHub Actions will no longer match the JWT `sub` claim.

## Modifying User Access

Update `terraform-admin/terraform.tfvars` and `terraform apply`.
