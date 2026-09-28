# Talos Kubernetes on Proxmox with OpenTofu

This project provisions two independent [Talos Linux](https://www.talos.dev/) Kubernetes environments, **dev** and **prod**, on Proxmox with OpenTofu, GitHub Actions, Doppler, and Argo CD. Both can add stateless AWS worker capacity. Each environment runs its own Argo CD, which manages only its own cluster. Cluster access is via `talosctl` / kubeconfig stored in Doppler (`TALOSCONFIG`, `KUBECONFIG`).

## Quick Start

1. **Doppler:** Follow [Doppler Setup](docs/doppler-setup.md) and enter the operator-issued secrets.
2. **Foundation and GitHub Actions:** Follow [Automated Deployment](docs/github-actions-setup.md). Applying `terraform/foundation/` locally creates the CI role, Doppler service tokens, and the `dev`/`prod` GitHub Environments.
3. **Access:** Follow [Cluster Access](docs/cluster-access.md) (`talosctl` + kubeconfig).
4. **Burst capacity:** Follow [AWS Burst Workers](docs/aws-burst-workers.md) to opt workloads in, roll back, and rotate keys.

## Layout

| Path                           | Role                                                                                        |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| `terraform/foundation/`        | Operator-applied: HCP workspaces, CI role, Doppler project/tokens, GitHub Environments      |
| `terraform/cluster/`           | CI, per environment: Proxmox, Talos, and AWS; writes generated credentials to Doppler       |
| `terraform/platform/`          | CI, per environment: Gateway API CRDs, Cilium, ESO token Secret, Argo CD and its root app   |
| `terraform/aws/`               | Stateless worker module used by the cluster root                                            |
| `terraform/cluster/env/{env}/` | Node inventory and network settings, also read by the platform root                         |
| `apps/components/`             | Helm wrappers for every in-cluster component                                                |
| `apps/argocd/`                 | `bootstrap` (AppProject and root Application) and `platform` (one Application per component) |

Roots hand data to each other only through Doppler. All state lives in HCP Terraform (free tier, local execution) in the workspaces `talos-proxmox` (foundation), `talos-cluster-${env}`, and `talos-platform-${env}`. See [Automated Deployment](docs/github-actions-setup.md) for the credential flow.
