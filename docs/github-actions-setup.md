# GitHub Actions Automated Deployment

This guide covers CI with GitHub Actions and HashiCorp Vault for Talos on Proxmox.

## Prerequisites

- [HashiCorp Vault Setup](./vault-setup.md)
- Tailscale (if using GitHub-hosted runners)
- GitHub repository `talos-proxmox` (JWT `sub` uses the post-2026-07-15 immutable format with owner/repo IDs; see `terraform-admin`)
- Proxmox API access
- MinIO (or S3) for Terraform state

**Do not apply** while the RKE2 cluster still occupies the same VM IDs and IPs.

## Step 1: Update VM Inventory

Edit `terraform-provision/env/{dev,prod}/k8s_nodes.json` and `longhorn_nodes.json`. Shape:

```json
{
  "dev-server1": {
    "vm_id": 111,
    "node": "pve",
    "role": "servers",
    "address": "10.69.1.111/16"
  }
}
```

`role` `servers` becomes Talos control plane. `longhorn` (and any non-`servers` k8s node) becomes a worker.

Edit `terraform-provision/env/{env}/network.json` for the API VIP, kube-vip LoadBalancer pool, and Traefik IP.

## Step 2: Set GitHub Variables

Repository → Settings → Secrets and variables → Actions → Variables:

| Variable | Value | Description |
| --- | --- | --- |
| `ENV_NAME` | `dev` or `prod` | Environment |
| `VAULT_ADDR` | `https://vault.example.com` | Vault address |
| `DESTROY` | `false` | Set `true` to destroy provisioned infra |

## Step 3: Set GitHub Secrets (Tailscale)

| Secret | Description |
| --- | --- |
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client |
| `TS_OAUTH_SECRET` | Tailscale OAuth secret |

## Step 4: Deploy

1. **Pull request:** Terraform plan + PR comment. No apply.
2. **Push to `main`:** Apply VMs + Talos, write `kv/{ENV}/talos`, then `apps/bootstrap.sh`. Helm reads kubeconfig from that Vault path, not from Terraform. In-cluster secrets (Longhorn MinIO) are created by bootstrap from Vault values CI already imported.

Provision state key: `talos-${ENV_NAME}.tfstate` (does not overwrite the RKE2 `dev.tfstate` / `prod.tfstate` keys).

## Destroy

1. Set `DESTROY=true`
2. Push to `main` or run `workflow_dispatch`
3. Workflow runs `terraform destroy` on provision

Helm releases are not torn down separately; destroying nodes removes the cluster.

## Next

[Cluster Access](./cluster-access.md)
