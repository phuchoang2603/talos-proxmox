# Talos Kubernetes on Proxmox with Terraform

This project provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on Proxmox using Terraform, GitHub Actions, and HashiCorp Vault. Cluster access is via `talosctl` / kubeconfig stored in Vault (`kv/{env}/talos`). Vault is also used for CI JWT and Proxmox/MinIO/Cloudflare secrets. GitHub Actions writes in-cluster secrets (for example Longhorn MinIO) at bootstrap; nothing in the cluster authenticates to Vault.

## Quick start

1. **Vault:** Follow [Vault Setup](docs/vault-setup.md).
2. **GitHub Actions:** Follow [Automated Deployment](docs/github-actions-setup.md). Bind JWT roles to this repository (`talos-proxmox`) via `terraform-admin`.
3. **Access:** Follow [Cluster Access](docs/cluster-access.md) (`talosctl` + kubeconfig).

## Layout

| Path                             | Role                                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `terraform-provision/env/{env}/` | Node inventory (`k8s_nodes.json`, `longhorn_nodes.json`) and `network.json` (VIP, LB range, Traefik IP) |
| `terraform-admin/`               | Vault JWT (GHA) and identity groups                                                                     |
| `apps/`                          | Helm charts and manifests (kube-vip LB, cert-manager, Traefik, Longhorn, Argo CD)                       |

Terraform provision state uses the MinIO key `talos-${ENV}.tfstate` so it does not collide with the RKE2 state until you destroy that cluster.

## Local tools

Nix flakes + direnv. Install [Nix](https://nixos.org/download.html) and [direnv](https://direnv.net/docs/installation.html), then `direnv allow` in the project root.
