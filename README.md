# Talos Kubernetes on Proxmox with Terraform

This project provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on Proxmox using Terraform, GitHub Actions, and Doppler. Cluster access is via `talosctl` / kubeconfig stored in Doppler (`TALOSCONFIG`, `KUBECONFIG`). GitHub Actions writes in-cluster secrets (Longhorn MinIO on prod) at bootstrap. The **argocd** cluster runs Argo CD for multi-cluster management.

## Quick start

1. **Doppler:** Follow [Doppler Setup](docs/doppler-setup.md).
2. **GitHub Actions:** Follow [Automated Deployment](docs/github-actions-setup.md). Store a read/write Doppler service token as `DOPPLER_TOKEN`.
3. **Access:** Follow [Cluster Access](docs/cluster-access.md) (`talosctl` + kubeconfig).

Progressive delivery is documented in [Argo Rollouts](docs/argo-rollouts.md).

## Layout

| Path | Role |
| --- | --- |
| `terraform-provision/env/{env}/` | Node inventory (`k8s_nodes.json`) and `network.json` |
| `apps/` | [Component configuration, bootstrap scripts, and manual Argo CD roots](apps/README.md) |

Terraform provision state uses the MinIO key `talos-${ENV}.tfstate` so it does not collide with the RKE2 state until you destroy that cluster.

## Local tools

Nix flakes + direnv. Install [Nix](https://nixos.org/download.html) and [direnv](https://direnv.net/docs/installation.html), then `direnv allow` in the project root. That provides `doppler`, `terraform`, `talosctl`, `kubectl`, and Helm. Then `doppler login`.
