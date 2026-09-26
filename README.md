# Talos Kubernetes on Proxmox with OpenTofu

This project provisions [Talos Linux](https://www.talos.dev/) Kubernetes clusters on Proxmox with OpenTofu, GitHub Actions, and Doppler. Dev and prod can add stateless AWS worker capacity. Cluster access is via `talosctl` / kubeconfig stored in Doppler (`TALOSCONFIG`, `KUBECONFIG`). The **argocd** cluster runs Argo CD for multi-cluster management.

## Quick Start

1. **Doppler:** Follow [Doppler Setup](docs/doppler-setup.md).
2. **GitHub Actions:** Follow [Automated Deployment](docs/github-actions-setup.md). Store a read/write Doppler service token as `DOPPLER_TOKEN`.
3. **Access:** Follow [Cluster Access](docs/cluster-access.md) (`talosctl` + kubeconfig).
4. **Burst capacity:** Follow [AWS Burst Workers](docs/aws-burst-workers.md) to opt workloads in, roll back, and rotate keys.

## Layout

| Path                           | Role                                                  |
| ------------------------------ | ----------------------------------------------------- |
| `terraform/identity/`          | GitHub OIDC CI role (separate local state)            |
| `terraform/cluster/`           | Cluster root; calls the Proxmox and AWS modules       |
| `terraform/aws/`               | Stateless worker module used by dev and prod          |
| `terraform/cluster/env/{env}/` | Node inventory and network settings                   |
| `apps/`                        | Components, bootstrap scripts, and Argo CD roots      |

Each cluster environment stores state in MinIO as `talos-${ENV}.tfstate`. See [Automated Deployment](docs/github-actions-setup.md) for the OIDC credential flow.
