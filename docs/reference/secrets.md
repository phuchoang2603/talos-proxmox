# Secrets reference

[Documentation home](../../README.md) · [Contributing and setup](../../CONTRIBUTING.md)

Doppler project `talos-proxmox` has one config per environment: `dev` and `prod`. Operators enter externally issued credentials; OpenTofu writes generated credentials; ESO delivers application Secrets to Kubernetes.

The repository's `.doppler.yaml` defaults to dev. Use explicit `--project talos-proxmox --config dev` or `--config prod` when reading or changing a config.

## Operator-entered secrets

Set these directly in the matching Doppler config before deployment. They are not foundation input variables.

| Doppler key | Consumer | Environments |
| --- | --- | --- |
| `HCP_TERRAFORM_TOKEN` | CI state access, exported as `TF_TOKEN_app_terraform_io` | Both |
| `PROXMOX_ENDPOINT`, `PROXMOX_USERNAME`, `PROXMOX_PASSWORD` | Cluster root's Proxmox provider | Both |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | GitHub runner's Tailscale connection | Both |
| `CLOUDFLARE_API_TOKEN` | Cloudflare operator, through the `cloudflare-credentials` ExternalSecret | Both |
| `CLOUDFLARE_TUNNEL_TOKEN` | `cloudflared`, through the same ExternalSecret | Both |
| `FLINK_RUSTFS_ACCESS_KEY`, `FLINK_RUSTFS_SECRET_KEY` | Dedicated `fraud-flink-prod` bucket user, delivered to Flink JobManager/TaskManager through `payment-gateway/flink-checkpoint-storage` | Prod |

`CLOUDFLARE_API_TOKEN` is a custom Cloudflare API token with **Account > Cloudflare Tunnel > Read**, **Account > Account Settings > Read**, and **Zone > DNS > Edit**, limited to the account and the `phuchoang.sbs` zone. `CLOUDFLARE_TUNNEL_TOKEN` is the token of the environment's tunnel (`dev-talos` or `prod-talos`); the ExternalSecret extracts the tunnel secret from it.

## Generated secrets

| Doppler key | Writer | Consumer |
| --- | --- | --- |
| `ESO_DOPPLER_TOKEN` | Foundation | Platform creates `kube-system/doppler-token` |
| `KUBECONFIG` | Cluster root | Platform providers and operators |
| `TALOSCONFIG` | Cluster root | Operators using `talosctl` |
| `KARPENTER_AWS_ACCESS_KEY_ID`, `KARPENTER_AWS_SECRET_ACCESS_KEY` | Cluster root's AWS module | Platform creates `kube-system/karpenter-aws` |
| `AWS_WORKER_MACHINE_CONFIG`, `AWS_WORKER_AMI_ID` | Cluster root's AWS module | Platform passes them to the Karpenter `EC2NodeClass` |
| `GRAFANA_ADMIN_PASSWORD` (prod) | Foundation | Grafana local admin login |
| `STARROCKS_ROOT_PASSWORD`, `STARROCKS_OPENMETADATA_PASSWORD`, `STARROCKS_RUSTFS_ACCESS_KEY`, `STARROCKS_RUSTFS_SECRET_KEY` (prod) | Operator | StarRocks setup Job: root and `openmetadata` passwords and the read-only catalog S3 identity; the password is also read by OpenMetadata ingestion workflows |
| `ML_AWS_ACCESS_KEY_ID`, `ML_AWS_SECRET_ACCESS_KEY` (prod) | Foundation | IAM user `talos-proxmox-ml`; ExternalSecret `fraud-ml-prod/ml-s3` |
| `ML_BUCKET` (prod) | Foundation | ML staging bucket name (contains the account ID); same `ml-s3` Secret |

Foundation generates the Grafana admin and ML storage credentials, so they survive environment destroys. Neither environment holds a credential for the other.

Foundation also creates a read/write CI service token per config and publishes it as that GitHub Environment's `DOPPLER_TOKEN` secret. This differs from the read-only ESO token. A local foundation apply uses a workspace-level Doppler login token to manage these service tokens.

## Credential boundaries

| Credential | Scope/use |
| --- | --- |
| CI Doppler token | Read/write one environment config |
| ESO Doppler token | Read one environment config; only Doppler credential installed in the cluster |
| CI AWS session | GitHub OIDC provisioning role |
| Karpenter AWS key | Launch, tag, and terminate the environment's tagged instances; regional Describe access |
| Cloudflare API token | Read tunnels in the account; edit DNS in the `phuchoang.sbs` zone. Dev and prod hold the same scope; ownership TXT records keep each operator to its own hostnames |
| HCP operator token | State access across the configured workspaces |

HCP state holds generated credentials and Talos bootstrap material. Doppler provider reads also bring secret data into the planning/state flow. Keep state and saved plans restricted to operators; sensitive plan rendering is not encryption of state.

## Delivery and rotation

| Kubernetes Secret | Namespace | Refresh |
| --- | --- | --- |
| `cloudflare-credentials` | `cloudflare-operator-system` | 1 hour |
| `grafana-admin`, `grafana-oidc` | `observability` (prod) | 1 hour |
| `dex-config`, `oauth2-proxy-credentials` | `auth` (prod) | 1 hour |

Each is produced by an ExternalSecret using the `doppler` ClusterSecretStore. If Doppler is unreachable, existing Secrets are retained and refresh failures are exposed through ESO status. Inspect status without printing secret values:

```bash
kubectl get clustersecretstore doppler
kubectl get externalsecrets -A
```

Select your cluster first using [cluster access](../operations/cluster-access.md).

For Cloudflare, change the key in Doppler and wait for the ExternalSecret to refresh. The operator reads `CLOUDFLARE_API_TOKEN` on each reconcile. The operator does not watch that Secret, so after changing `CLOUDFLARE_TUNNEL_TOKEN`, use Argo CD's **Restart** action on `cloudflare-operator-controller-manager` (it rewrites the tunnel credentials on startup), then on the `talos-proxmox` `cloudflared` Deployment. Updating a Kubernetes Secret does not restart Deployments automatically. After rotating the Grafana admin password, restart Grafana. Dex reads `dex-config` only at startup, so after rotating `AUTH_OIDC_CLIENT_SECRET`, wait for the refresh and restart Dex and its clients, including Grafana. Restart Dex after the first sync of a config change too. The Karpenter key is not delivered by ESO: rotate it with the [OpenTofu procedure](../operations/aws-burst-workers.md#rotate-the-karpenter-key), where the platform apply restarts the controller.
