# Secrets reference

[Documentation home](../../README.md) · [Contributing and setup](../../CONTRIBUTING.md)

Doppler project `talos-proxmox` has one config per environment: `dev` and `prod`. Operators enter externally issued credentials; OpenTofu writes generated credentials; ESO delivers application Secrets to Kubernetes.

The repository's `.doppler.yaml` defaults to dev. Use explicit `--project talos-proxmox --config dev` or `--config prod` when reading or changing a config.

## Operator-entered secrets

The foundation root accepts a sensitive `operator_secrets` map keyed by environment and writes only the keys in this table. Keep its `.tfvars.json` file outside Git with mode `0600`, and pass that same file to every foundation plan/apply. Application credentials are not managed by foundation; enter them in Doppler by hand.

| Doppler key | Consumer | Environments |
| --- | --- | --- |
| `HCP_TERRAFORM_TOKEN` | CI state access, exported as `TF_TOKEN_app_terraform_io` | Both |
| `PROXMOX_ENDPOINT`, `PROXMOX_USERNAME`, `PROXMOX_PASSWORD` | Cluster root's Proxmox provider | Dev |
| `CLOUD_MANAGEMENT_CIDRS` | JSON array of stable operator IPv4 CIDRs; CI adds its current egress /32 | Prod |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | GitHub runner's Tailscale connection | Dev |
| `CLOUDFLARE_API_TOKEN` | Cloudflare operator, through the `cloudflare-credentials` ExternalSecret | Both |
| `CLOUDFLARE_TUNNEL_TOKEN` | `cloudflared`, through the same ExternalSecret | Both |

`CLOUDFLARE_API_TOKEN` is a custom Cloudflare API token with **Account > Cloudflare Tunnel > Read**, **Account > Account Settings > Read**, and **Zone > DNS > Edit**, limited to the account and the `phuchoang.sbs` zone. `CLOUDFLARE_TUNNEL_TOKEN` is the token of the environment's tunnel (`dev-talos` or `prod-talos`); the ExternalSecret extracts the tunnel secret from it.

## Generated secrets

| Doppler key | Writer | Consumer |
| --- | --- | --- |
| `ESO_DOPPLER_TOKEN` | Foundation | Platform creates `kube-system/doppler-token` |
| `KUBECONFIG` | Cluster root | Platform providers and operators |
| `TALOSCONFIG` | Cluster root | Operators using `talosctl` |
| `AUTOSCALER_CREDENTIALS` | Selected cluster module; JSON map of `key.json` for GCP or AWS access-key environment variables | Platform creates `kube-system/cluster-autoscaler-cloud` |
| `BLOCK_STORAGE_CREDENTIALS` | Selected cluster module; JSON credential map | ESO creates the selected CSI driver's Secret |
| `AUTOSCALER_GROUPS`, `CLOUD_PROJECT_ID`, `CLOUD_REGION`, `CLOUD_ZONE` | Cluster root | Platform configures explicit Autoscaler group bounds and GCE API location |
| `TALOS_IMAGE_ID` | Selected foundation module | Production cloud instances/templates |
| `TALOS_GPU_IMAGE_ID` | GCP foundation module | Fixed production GCP GPU worker |
| `CLOUD_PROVIDER` | Foundation | CI and platform select GCP or AWS |
| `GRAFANA_ADMIN_PASSWORD` (both environments) | Operator | Grafana local admin login |
| Application/database passwords, OIDC client secrets, signing keys and catalog credentials | Operator | Entered by hand per environment |
| `OBJECT_<PURPOSE>_ACCESS_KEY_ID`, `OBJECT_<PURPOSE>_SECRET_ACCESS_KEY` (prod) | Foundation | Separate GCS HMAC or S3 IAM identities for training, artifacts, substrate and gateway; dev MinIO credentials remain externally provisioned |
| `OBJECT_STORAGE_BUCKET`, `OBJECT_<PURPOSE>_BUCKET` (prod) | Foundation | GCP aliases all name the shared platform bucket; AWS retains separate purpose buckets |
| `OBJECT_STORAGE_ENDPOINT`, `OBJECT_STORAGE_REGION` (prod) | Foundation | Selected cloud object-storage endpoint and signing region |

Foundation generates production object-storage credentials, so they survive environment destroys. HCP state access and the scoped Cloudflare API token may be shared. Tunnel tokens remain specific to each existing tunnel; cluster, autoscaler, ESO and application credentials remain independent. Do not restore kubeconfigs, Talos bootstrap material, image IDs or controller credentials belonging to deleted resources.

Foundation also creates a read/write CI service token per config and publishes it as that GitHub Environment's `DOPPLER_TOKEN` secret. This differs from the read-only ESO token. A local foundation apply uses a workspace-level Doppler login token to manage these service tokens.

## Credential boundaries

| Credential | Scope/use |
| --- | --- |
| CI Doppler token | Read/write one environment config |
| ESO Doppler token | Read one environment config; only Doppler credential installed in the cluster |
| CI cloud session | GitHub Workload Identity Federation on GCP or OIDC role assumption on AWS; production only |
| Autoscaler credentials | Read cloud inventory and resize/remove nodes only through configured MIGs or ASGs |
| CSI credentials | Provision, resize, attach and detach cloud block volumes; no object access |
| Cloudflare API token | Read tunnels in the account; edit DNS in the `phuchoang.sbs` zone. Dev and prod hold the same scope; ownership TXT records keep each operator to its own hostnames |
| HCP operator token | State access across the configured workspaces |

HCP state holds generated credentials and Talos bootstrap material. Doppler provider reads also bring secret data into the planning/state flow. Keep state and saved plans restricted to operators; sensitive plan rendering is not encryption of state.

## Delivery and rotation

| Kubernetes Secret | Namespace | Refresh |
| --- | --- | --- |
| `cloudflare-credentials` | `operators` | 1 hour |
| `grafana-admin`, `grafana-oidc` | `observability` (both) | 1 hour |
| `dex-config`, `oauth2-proxy-credentials` | `auth` (both) | 1 hour |

Each is produced by an ExternalSecret using the `doppler` ClusterSecretStore. If Doppler is unreachable, existing Secrets are retained and refresh failures are exposed through ESO status. Inspect status without printing secret values:

```bash
kubectl get clustersecretstore doppler
kubectl get externalsecrets -A
```

Select your cluster first using [cluster access](../operations/cluster-access.md).

For Cloudflare, change the key in Doppler and wait for the ExternalSecret to refresh. The operator reads `CLOUDFLARE_API_TOKEN` on each reconcile. The operator does not watch that Secret, so after changing `CLOUDFLARE_TUNNEL_TOKEN`, use Argo CD's **Restart** action on `cloudflare-operator-controller-manager` (it rewrites the tunnel credentials on startup), then on the `talos-proxmox` `cloudflared` Deployment. Updating a Kubernetes Secret does not restart Deployments automatically. After rotating the Grafana admin password, restart Grafana. Dex reads `dex-config` only at startup, so after rotating `AUTH_OIDC_CLIENT_SECRET`, wait for the refresh and restart Dex and its clients, including Grafana. Restart Dex after the first sync of a config change too. The Autoscaler key is not delivered by ESO: rotate it with the [OpenTofu procedure](../operations/gcp-workers.md#rotate-controller-keys), where the platform apply restarts the controller. CSI credentials refresh through ESO; restart its controller after rotation.
