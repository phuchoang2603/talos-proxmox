# Talos on Proxmox and AWS

Two independent Kubernetes environments run Talos: **dev** on the existing Proxmox hosts and **prod** in AWS. OpenTofu provisions infrastructure, each cluster's Argo CD manages applications, and Doppler supplies credentials.

Dev keeps the former production VM allocations with one control-plane/workload node and two workers. Prod uses one On-Demand `m6a.large` control-plane/workload node and two `m6a.xlarge` On-Demand workers with optional Spot burst capacity managed by Karpenter. Both run the same applicable platform, including Knative and Kubeflow. Each has a single control plane and single-instance PostgreSQL; neither is highly available.

Dev uses local-path and existing MinIO. Prod uses encrypted gp3 EBS and generic private S3 storage. An authenticated PostgreSQL-backed Polaris catalog provides the shared Iceberg REST interface. State, application credentials and public domains remain independent.

## Start here

| I want to… | Read |
| --- | --- |
| Contribute, validate, or deploy | [Contributing and setup](CONTRIBUTING.md) |
| Understand provisioning, state, and CI | [Terraform and CI architecture](docs/architecture/terraform-ci.md) |
| Understand AWS networking and autoscaling | [Hybrid AWS worker architecture](docs/architecture/hybrid-aws-workers.md) |
| Understand application ownership and reconciliation | [GitOps and Argo CD architecture](docs/architecture/gitops.md) |
| Connect to a cluster or check its health | [Cluster access](docs/operations/cluster-access.md) |
| Schedule burst workloads or rotate their AWS key | [AWS worker operations](docs/operations/aws-burst-workers.md) |
| Find a credential's source and consumers | [Secrets reference](docs/reference/secrets.md) |

## Repository map

| Path | Contents |
| --- | --- |
| [`terraform/foundation/`](terraform/foundation/) | Operator-applied identities, Doppler tokens, GitHub Environments, HCP workspaces |
| [`terraform/cluster/`](terraform/cluster/) | Separate dev/prod infrastructure entrypoints and environment inventory |
| [`terraform/platform/`](terraform/platform/) | Per-environment CNI, Gateway API CRDs, ESO authentication, Argo CD bootstrap |
| [`terraform/proxmox/`](terraform/proxmox/) and [`terraform/aws/`](terraform/aws/) | Modules called by the cluster root |
| [`apps/argocd/`](apps/argocd/) | Bootstrap and shared platform Application charts |
| [`apps/components/`](apps/components/) | Component charts, vendored dependencies, environment overrides |
| [`.github/workflows/`](.github/workflows/) | Validation and provisioning workflows |
| [`openspec/`](openspec/) | Behavior specifications and archived change records |

Use `devenv shell` for the project's OpenTofu, Helm, Doppler, Talos, and Kubernetes tools. The [deployment guide](CONTRIBUTING.md) explains the account access and external services required before applying anything.
