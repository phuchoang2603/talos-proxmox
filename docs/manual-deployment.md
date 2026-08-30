# Manual Deployment

Run Terraform and Helm from a machine that can reach Proxmox, Vault, MinIO, and the node network (or Tailscale).

## Prerequisites

- Terraform 1.6.6, Helm, kubectl, talosctl (`direnv allow` in this repo)
- Vault login
- Direct or VPN access to Proxmox and Talos APIs (port 50000)

IPs (`vip`, `lb_range`, `ingress`) are git-managed in `terraform-provision/env/{env}/network.json`, not Vault.

## Environment

```bash
export VAULT_ADDR="https://vault.example.com"
vault login
export VAULT_TOKEN   # required so Terraform can write kv/{env}/talos

export AWS_ACCESS_KEY_ID=$(vault kv get -field=access_key kv/shared/minio)
export AWS_SECRET_ACCESS_KEY=$(vault kv get -field=secret_key kv/shared/minio)

export TF_VAR_env=dev

# Proxmox — match keys stored under kv/shared/proxmox
export TF_VAR_proxmox_endpoint=$(vault kv get -field=endpoint kv/shared/proxmox)
export TF_VAR_proxmox_username=$(vault kv get -field=username kv/shared/proxmox)
export TF_VAR_proxmox_password=$(vault kv get -field=password kv/shared/proxmox)
```

## Provision

```bash
cd terraform-provision
terraform init --backend-config="key=talos-dev.tfstate"
terraform plan -var-file=env/dev/main.tfvars
terraform apply -var-file=env/dev/main.tfvars
```

Apply writes `talosconfig` and `kubeconfig` to `kv/dev/talos`. Pull them from Vault (see [Cluster Access](./cluster-access.md)):

```bash
vault kv get -field=kubeconfig kv/dev/talos > ../kubeconfig
vault kv get -field=talosconfig kv/dev/talos > ../talosconfig
chmod 600 ../kubeconfig ../talosconfig
export KUBECONFIG="$PWD/../kubeconfig"
export TALOSCONFIG="$PWD/../talosconfig"
```

## Apps

```bash
cd ../apps
export ENV_NAME=dev
export IP_LB_RANGE=$(jq -r .lb_range ../terraform-provision/env/dev/network.json)
export IP_INGRESS=$(jq -r .ingress ../terraform-provision/env/dev/network.json)
export SSL_DOMAIN=$(vault kv get -field=domain kv/shared/cloudflare)
export SSL_API_TOKEN=$(vault kv get -field=api_token kv/shared/cloudflare)
export SSL_EMAIL=$(vault kv get -field=email kv/shared/cloudflare)
export VAULT_ADDR
./bootstrap.sh
```

## Destroy

```bash
cd terraform-provision
terraform destroy -var-file=env/dev/main.tfvars
```
