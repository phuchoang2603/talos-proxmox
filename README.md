# Talos Kubernetes on Proxmox with Terraform

This project provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on Proxmox using Terraform, GitHub Actions, and HashiCorp Vault. Cluster access is via `talosctl` / kubeconfig stored in Vault (`kv/{env}/talos`). Vault is also used for CI JWT, Proxmox/MinIO/Cloudflare secrets, and External Secrets.

**Cutover:** Destroy the RKE2 VMs before applying this stack if you reuse the same VM IDs and IPs. This repo is intended to become the live cluster; kubernetes-proxmox remains a learning archive.

## Quick start

1. **Vault:** Follow [Vault Setup](docs/vault-setup.md).
2. **GitHub Actions:** Follow [Automated Deployment](docs/github-actions-setup.md). Bind JWT roles to this repository (`talos-proxmox`) via `terraform-admin`.
3. **Access:** Follow [Cluster Access](docs/cluster-access.md) (`talosctl` + kubeconfig).
4. **Secrets in-cluster:** [External Secrets Operator](docs/external-secrets-vault-integration.md).

## Layout

| Path | Role |
| --- | --- |
| `terraform-provision/env/{env}/` | Node inventory (`k8s_nodes.json`, `longhorn_nodes.json`) and `network.json` (VIP, LB range, Traefik IP) |
| `terraform-admin/` | Vault JWT (GHA), identity groups, Kubernetes auth for ESO |
| `apps/` | Helm charts and manifests (kube-vip LB, cert-manager, Traefik, Longhorn, Argo CD, ESO) |

Terraform provision state uses the MinIO key `talos-${ENV}.tfstate` so it does not collide with the RKE2 state until you destroy that cluster.

## Local tools

Nix flakes + direnv. Install [Nix](https://nixos.org/download.html) and [direnv](https://direnv.net/docs/installation.html), then `direnv allow` in the project root.

For a laptop apply, see [Manual Deployment](docs/manual-deployment.md).
