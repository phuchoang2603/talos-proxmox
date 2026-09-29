# Contributing

[Documentation home](README.md) · [Terraform and CI architecture](docs/architecture/terraform-ci.md)

Use this guide to make changes, validate them, and deploy dev and prod. Commands assume you start at the repository root. For an existing deployment, go straight to [cluster access](docs/operations/cluster-access.md).

## Make a change

1. Create a branch and enter `devenv shell`.
2. Update the relevant Terraform root or component chart. Use the [repository map](README.md#repository-map) and [ownership guide](docs/architecture/gitops.md#one-owner-per-resource) to choose the right location.
3. Run the relevant checks below and update documentation or OpenSpec requirements when behavior changes.
4. Open a pull request targeting `main`, describing the change and validation performed. PR checks run without deployment credentials or state access.
5. After review, merging to `main` triggers provisioning for both environments. Foundation changes still require a local operator apply.

Editing documentation and running static checks do not require deployment credentials. The account setup below is for provisioning and authenticated plans.

## Validate locally

For a changed Terraform root, replace `cluster` with `foundation` or `platform` as appropriate:

```bash
tofu -chdir=terraform/cluster fmt -check -recursive
tofu -chdir=terraform/cluster init -backend=false
tofu -chdir=terraform/cluster validate
```

For a component chart, lint its base values and any changed environment overlay. For example:

```bash
helm lint apps/components/karpenter --kube-version 1.36.3
helm lint apps/components/karpenter --kube-version 1.36.3 \
  --values apps/components/karpenter/environments/prod/values.yaml
```

For changes to platform membership, check both environments:

```bash
for cluster in dev prod; do
  helm lint apps/argocd/platform --kube-version 1.36.3 --set cluster="$cluster"
done
```

[The lint workflow](.github/workflows/lint.yml) defines the full CI checks for all roots, charts, and environment overlays.

## 1. Prepare local tools and account access

```bash
devenv shell
doppler login
tofu login app.terraform.io
```

The shell provides OpenTofu, Helm, Doppler, `talosctl`, and `kubectl`. Foundation setup also uses the GitHub CLI (`gh`, authenticated with `gh auth login`) and an authenticated AWS session with permission to manage the foundation resources. Install those separately if they are not already available.

You need access to Proxmox, AWS, GitHub, Doppler, HCP Terraform, and a Tailscale network through which GitHub runners can reach the private Proxmox and cluster APIs. Configure Tailscale OAuth credentials and access for the runner's `tag:ci` identity.

The checked-in configuration targets GitHub owner and HCP organization `phuchoang2603`, repository and Doppler project `talos-proxmox`, and AWS region `us-east-1`. If using different accounts, update:

| Setting | File |
| --- | --- |
| HCP organization and GitHub owner | [`terraform/foundation/main.tf`](terraform/foundation/main.tf) |
| HCP organization for cluster/platform state | [`cluster/provider.tf`](terraform/cluster/provider.tf), [`platform/provider.tf`](terraform/platform/provider.tf) |
| GitHub repository and OIDC subject, including immutable owner/repository IDs | [`foundation/github.tf`](terraform/foundation/github.tf), [`foundation/aws.tf`](terraform/foundation/aws.tf) |
| CI AWS role ARN and region | [`provision.yml`](.github/workflows/provision.yml) |
| Git repository reconciled by Argo CD | [`platform/variables.tf`](terraform/platform/variables.tf) |

## 2. Prepare Doppler and HCP Terraform

The foundation root **imports an existing Doppler project and its dev/prod environments**. Make sure project `talos-proxmox` and root configs `dev` and `prod` exist before applying it.

1. Create the HCP Terraform organization and set its default execution mode to **Local** before initializing foundation. Plans will run on your machine or the CI runner; HCP stores and locks state.
2. Create an HCP user token for an operator with access to the organization. Store it as `HCP_TERRAFORM_TOKEN` in both Doppler configs. This deployment uses an operator user token shared across the workspaces.
3. Enter the operator-issued credentials listed in the [secrets reference](docs/reference/secrets.md#operator-entered-secrets), including Proxmox, Tailscale, and Cloudflare credentials.

Foundation creates the CI and ESO service tokens. Cluster applies generate kubeconfigs, Talos configs, and Karpenter AWS keys and worker configuration. You do not enter those by hand.

## 3. Review inventory and network settings

| Configuration | Location |
| --- | --- |
| VM placement, sizing, addresses, roles, PCI passthrough | [`terraform/cluster/env/`](terraform/cluster/env/), each environment's `k8s_nodes.json` |
| API VIP and LoadBalancer address range | Each environment's `network.json` |
| Proxmox bridge, datastore, gateway, versions, AWS AMI and VPC CIDR | Each environment's `main.tfvars` |
| Cilium address pools and L2 announcement nodes | [`cilium-network/environments/`](apps/components/cilium-network/environments/) |
| Argo CD UI addresses | [`argocd/bootstrap/environments/`](apps/argocd/bootstrap/environments/) |

Inventory role `servers` means a control-plane node that also runs workloads; `worker` means a general worker. A node's `pci` entries enable GPU passthrough and select the Talos image with NVIDIA extensions.

Keep Cilium's address pools consistent with `network.json`, choose UI addresses from those pools, and keep L2 announcement selectors consistent with node names. These settings are maintained in separate files.

AWS workers use a dedicated VPC per environment and a public subnet. Check the pinned AMI, availability zone, and [network prerequisites](docs/architecture/hybrid-aws-workers.md#network-path) before provisioning.

## 4. Apply foundation locally

Use a Doppler workspace-level login token here; the config-scoped CI token cannot create service tokens. Start with your local AWS session active and no cluster/platform `TF_WORKSPACE` selection left over:

```bash
unset TF_WORKSPACE
export DOPPLER_TOKEN="$(doppler configure get token --plain)"
export GITHUB_TOKEN="$(gh auth token)"

tofu -chdir=terraform/foundation init
tofu -chdir=terraform/foundation plan
tofu -chdir=terraform/foundation apply
```

Review the plan before approving the apply. Existing Doppler project/environment resources should be imported, not replaced. Foundation creates the four cluster/platform HCP workspaces in local execution mode, AWS CI identity, main-only GitHub Environments, and Doppler tokens. Its own state uses workspace `talos-proxmox`.

## 5. Deploy through GitHub Actions

Push the reviewed configuration to `main`. The **Provision** workflow validates the repository, then runs dev and prod independently. For each environment it applies the cluster root followed by the platform root.

For one environment, use **Actions → Manual Provision → Run workflow**, select `main`, the environment, and **apply**. A dispatch from another branch cannot provision.

A green workflow means both OpenTofu applies completed. Check Argo CD convergence separately using [cluster access](docs/operations/cluster-access.md#check-convergence): the root Application and its children should become Synced and Healthy, including storage and SPIRE.

## Run OpenTofu locally

Use this for inspection or an operator-driven change. Start at the repository root with a local AWS session for the cluster root, a Doppler login, and HCP credentials from `tofu login`:

```bash
export TF_VAR_env=dev
export DOPPLER_TOKEN="$(doppler configure get token --plain)"
export TF_WORKSPACE="talos-cluster-${TF_VAR_env}"

tofu -chdir=terraform/cluster init
tofu -chdir=terraform/cluster plan -var-file="env/${TF_VAR_env}/main.tfvars"
```

For platform, select its workspace and use no variable file:

```bash
export TF_WORKSPACE="talos-platform-${TF_VAR_env}"
tofu -chdir=terraform/platform init
tofu -chdir=terraform/platform plan
```

Both roots reject a workspace belonging to the other environment. The platform root requires working cluster credentials already written to Doppler by the cluster apply. Use `tofu apply` only after reviewing the relevant plan.

## Destroy an environment

Use **Manual Provision** on `main`, select the environment, then **destroy**. The workflow destroys the cluster root, including the AWS worker infrastructure, Karpenter's instances, and its key, and then empties the platform root's state. See [Destroy an environment](docs/operations/aws-burst-workers.md#destroy-an-environment). Foundation is separate and remains in place. This removes the environment's infrastructure; preserve any data you need beforehand.
