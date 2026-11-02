# Contributing

[Documentation home](README.md) · [Terraform and CI architecture](docs/architecture/terraform-ci.md)

Use this guide to make changes, validate them, and deploy dev and prod. Commands assume you start at the repository root. For an existing deployment, go straight to [cluster access](docs/operations/cluster-access.md).

## Make a change

1. Create a branch and enter `devenv shell`.
2. Update the relevant Terraform root or component chart. Use the [repository map](README.md#repository-map) and [ownership guide](docs/architecture/gitops.md#one-owner-per-resource) to choose the right location.
3. Run the relevant checks below and update documentation or OpenSpec requirements when behavior changes.
4. Open a pull request targeting `main`, describing the change and validation performed. Validation runs without state or deployment credentials. Trusted repository PRs then deploy dev; fork PRs validate only.
5. After review, repository PRs and `main` deploy dev after validation; trusted PRs also plan prod. Deploy prod manually from `main`. Foundation changes still require a local operator apply.

Editing documentation and running static checks do not require deployment credentials. The account setup below is for provisioning and authenticated plans.

## Validate locally

For a changed Terraform root, replace `cluster/dev` with `cluster/prod`, `foundation` or `platform` as appropriate:

```bash
tofu -chdir=terraform/cluster/dev fmt -check -recursive
tofu -chdir=terraform/cluster/dev init -backend=false
tofu -chdir=terraform/cluster/dev validate
```

For a component chart, lint its base values and any changed environment overlay. For example:

```bash
helm lint apps/components/kubeflow --kube-version 1.37.2
helm lint apps/components/kubeflow --kube-version 1.37.2 \
  --values apps/components/kubeflow/environments/prod/values.yaml
```

For changes to platform membership, check both environments:

```bash
for cluster in dev prod; do
  helm lint apps/argocd/platform --kube-version 1.37.2 --set cluster="$cluster"
done
```

[The lint workflow](.github/workflows/lint.yml) defines the full CI checks for all roots, charts, and environment overlays.

The Terraform roots target fresh deployments and contain no legacy state migration blocks. Static checks do not require cloud credentials.

## 1. Prepare local tools and account access

```bash
devenv shell
doppler login
tofu login app.terraform.io
```

The shell provides OpenTofu, Helm, Doppler, `talosctl`, and `kubectl`. Foundation setup also uses the GitHub CLI (`gh`, authenticated with `gh auth login`) and Google Cloud CLI. Both are provided by devenv. Authenticate with `gcloud auth login` and `gcloud auth application-default login`, then run `gcloud config set project talos-proxmox`. The project must already exist with billing enabled, and the operator needs permission to enable APIs and manage Compute, IAM, storage/HMAC keys and federation. Organizational policy must allow the generated service-account keys.

You need access to Proxmox, GCP, GitHub, Doppler, HCP Terraform, and a Tailscale network through which GitHub runners can reach the private Proxmox and cluster APIs. Configure Tailscale OAuth credentials and access for the runner's `tag:ci` identity.

The checked-in configuration targets GitHub owner and HCP organization `phuchoang2603`, repository and Doppler project `talos-proxmox`, and GCP project `talos-proxmox` in region `us-central1`. If using different accounts, update:

| Setting | File |
| --- | --- |
| HCP organization and GitHub owner | [`terraform/foundation/main.tf`](terraform/foundation/main.tf) |
| HCP organization for cluster/platform state | [`cluster/dev/provider.tf`](terraform/cluster/dev/provider.tf), [`cluster/prod/provider.tf`](terraform/cluster/prod/provider.tf), [`platform/provider.tf`](terraform/platform/provider.tf) |
| GitHub repository and GCP federation restrictions, including immutable owner/repository IDs | [`foundation/github.tf`](terraform/foundation/github.tf), [`foundation/gcp.tf`](terraform/foundation/gcp.tf) |
| GCP project/region and CI federation | [`foundation/gcp.tf`](terraform/foundation/gcp.tf), [`cluster/env/prod/main.tfvars`](terraform/cluster/env/prod/main.tfvars); foundation publishes the GitHub Environment variables |
| Git repository reconciled by Argo CD | [`platform/variables.tf`](terraform/platform/variables.tf) |

## 2. Prepare Doppler and HCP Terraform

The foundation root creates the Doppler project and dev/prod configs from empty state. Supply operator-issued credentials through a private `operator_secrets` variable file outside Git; enter application credentials in Doppler by hand.

1. Create the HCP Terraform organization and set its default execution mode to **Local** before initializing foundation. Plans will run on your machine or the CI runner; HCP stores and locks state.
2. Create an HCP user token for an operator with access to the organization. Store it as `HCP_TERRAFORM_TOKEN` in both Doppler configs. This deployment uses an operator user token shared across the workspaces.
3. Enter the operator-issued credentials listed in the [secrets reference](docs/reference/secrets.md#operator-entered-secrets), including Proxmox, Tailscale, and Cloudflare credentials.

Foundation creates the CI and ESO service tokens. Cluster applies generate kubeconfigs, Talos configs, Autoscaler/CSI service-account keys and worker configuration. Foundation builds the Talos GCE image by default or publishes the operator-provided AWS Talos AMI. Select the same `cloud_provider` for foundation and production; see [AWS deployment](docs/operations/gcp-workers.md#optional-aws-infrastructure). Set `CLOUD_MANAGEMENT_CIDRS` in prod Doppler to a JSON array of stable operator IPv4 CIDRs (/24 or narrower); CI adds its own egress /32.

## 3. Review inventory and network settings

| Configuration | Location |
| --- | --- |
| VM placement, sizing, addresses, roles, PCI passthrough | [`terraform/cluster/env/`](terraform/cluster/env/), dev's `k8s_nodes.json` |
| Proxmox bridge, datastore, gateway, versions, GCP project, zone and machine sizes | Each environment's `main.tfvars` |

Inventory role `servers` means a control-plane node that also runs workloads; `worker` means a general worker. A node's `pci` entries enable GPU passthrough and select the Talos image with NVIDIA extensions.

Dev addresses its single control-plane node directly; prod uses a stable GCP regional public address. Application UIs use ClusterIP Services, Cloudflare tunnels and management port-forward.

Prod uses a dedicated single-zone VPC/subnet and public egress addresses; dev provisions no cloud resources. Check the GCE image, zone, quotas, and [network prerequisites](docs/architecture/gcp-workers.md#networking) before provisioning.

## 4. Apply foundation locally

Use a Doppler workspace-level login token here; the config-scoped CI token cannot create service tokens. Start with your local GCP CLI and application-default credentials active and no cluster/platform `TF_WORKSPACE` selection left over:

```bash
unset TF_WORKSPACE
export DOPPLER_TOKEN="$(doppler configure get token --plain)"
export GITHUB_TOKEN="$(gh auth token)"

tofu -chdir=terraform/foundation init
tofu -chdir=terraform/foundation plan -var-file="$OPERATOR_VARS_FILE"
tofu -chdir=terraform/foundation apply -var-file="$OPERATOR_VARS_FILE"
```

Review the plan before approving the apply. Pass the same private operator variable file on every foundation plan/apply. Foundation creates the four cluster/platform HCP workspaces in local execution mode, GCP CI identity, main-only GitHub Environments, and Doppler tokens. Its own state uses workspace `talos-proxmox`.

## 5. Deploy through GitHub Actions

Push the reviewed configuration to `main`. **Provision** validates trusted repository PRs, deploys them to dev and independently plans prod. Main deploys dev only. Apply prod through **Manual Provision** using a selected main commit; root and child Argo Applications stay pinned to that SHA.

To build dev or update it manually, use **Actions → Manual Provision → Run workflow**, select `main`, `dev`, and **apply**. Select **destroy** when you are done. The same workflow can also apply or destroy prod. A dispatch from another branch cannot provision.

A green workflow means the OpenTofu applies completed. Check Argo CD convergence separately using [cluster access](docs/operations/cluster-access.md#check-convergence): the root Application and its children should become Synced and Healthy, including storage, Knative and Kubeflow.

## Run OpenTofu locally

Use this for inspection or an operator-driven change. Start at the repository root with local GCP CLI/application-default credentials for prod (dev needs Proxmox access), a Doppler login, and HCP credentials from `tofu login`:

```bash
export TF_VAR_env=dev
export TF_VAR_target_revision="$(git rev-parse HEAD)"
export DOPPLER_TOKEN="$(doppler configure get token --plain)"
export TF_WORKSPACE="talos-cluster-${TF_VAR_env}"

tofu -chdir=terraform/cluster/${TF_VAR_env} init
tofu -chdir=terraform/cluster/${TF_VAR_env} plan -var-file="../env/${TF_VAR_env}/main.tfvars"
```

For platform, select its workspace and use no variable file:

```bash
export TF_WORKSPACE="talos-platform-${TF_VAR_env}"
tofu -chdir=terraform/platform init
tofu -chdir=terraform/platform plan
```

Both roots reject a workspace belonging to the other environment. The platform root requires working cluster credentials already written to Doppler by the cluster apply. Use `tofu apply` only after reviewing the relevant plan.

## Destroy an environment

Use **Manual Provision** on `main`, select the environment, then **destroy**. The workflow destroys the cluster root, including the GCE managed worker groups and controller credentials, and then empties the platform root's state. See [Deploy or destroy](docs/operations/gcp-workers.md#deploy-or-destroy). Foundation is separate and remains in place. This removes the environment's infrastructure; preserve any data you need beforehand.
