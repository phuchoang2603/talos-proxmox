# Talos Kubernetes on Proxmox with Terraform

This project provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on Proxmox using Terraform, GitHub Actions, and Doppler. Cluster access is via `talosctl` / kubeconfig stored in Doppler (`TALOSCONFIG`, `KUBECONFIG`). The **argocd** cluster runs Argo CD for multi-cluster management.

## Quick Start

1. **Doppler:** Follow [Doppler Setup](docs/doppler-setup.md).
2. **GitHub Actions:** Follow [Automated Deployment](docs/github-actions-setup.md). Store a read/write Doppler service token as `DOPPLER_TOKEN`.
3. **Access:** Follow [Cluster Access](docs/cluster-access.md) (`talosctl` + kubeconfig).

## Layout

| Path                           | Role                                                                 |
| ------------------------------ | -------------------------------------------------------------------- |
| `terraform/cluster/env/{env}/` | Node inventory (`k8s_nodes.json`) and `network.json`                 |
| `apps/`                        | Component configuration, bootstrap scripts, and manual Argo CD roots |

Terraform provision state uses the MinIO key `talos-${ENV}.tfstate` so it does not collide with the RKE2 state until you destroy that cluster.
