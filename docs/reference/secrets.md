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
| `CLOUDFLARE_TUNNEL_TOKEN` | Tunnel ExternalSecret | Both |
| `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY` | Longhorn backup ExternalSecret | prod |

`LONGHORN_AWS_*` are MinIO backup credentials despite their names; they are separate from the autoscaler's AWS IAM credentials.

## Generated secrets

| Doppler key | Writer | Consumer |
| --- | --- | --- |
| `ESO_DOPPLER_TOKEN` | Foundation | Platform creates `external-secrets-auth/doppler-token` |
| `KUBECONFIG` | Cluster root | Platform providers and operators |
| `TALOSCONFIG` | Cluster root | Platform health checks and operators |
| `AUTOSCALER_AWS_ACCESS_KEY_ID`, `AUTOSCALER_AWS_SECRET_ACCESS_KEY` | Cluster root's AWS module | Autoscaler ExternalSecret |

Foundation also creates a read/write CI service token per config and publishes it as that GitHub Environment's `DOPPLER_TOKEN` secret. This differs from the read-only ESO token. A local foundation apply uses a workspace-level Doppler login token to manage these service tokens.

## Credential boundaries

| Credential | Scope/use |
| --- | --- |
| CI Doppler token | Read/write one environment config |
| ESO Doppler token | Read one environment config; only Doppler credential installed in the cluster |
| CI AWS session | GitHub OIDC provisioning role |
| Autoscaler AWS key | Scale the environment's named ASG; account-wide Describe access |
| HCP operator token | State access across the configured workspaces |

HCP state holds generated credentials and Talos bootstrap material. Doppler provider reads also bring secret data into the planning/state flow. Keep state and saved plans restricted to operators; sensitive plan rendering is not encryption of state.

## Delivery and rotation

| Kubernetes Secret | Namespace | Refresh |
| --- | --- | --- |
| `cluster-autoscaler-aws` | `cluster-autoscaler` | 5 minutes |
| `cloudflare-tunnel-token` | `cloudflare-tunnel` | 1 hour |
| `longhorn-minio-credentials` | `longhorn-system` | 1 hour |

All three are produced by ExternalSecrets using the `doppler` ClusterSecretStore. If Doppler is unreachable, existing Secrets are retained and refresh failures are exposed through ESO status. Inspect status without printing secret values:

```bash
kubectl get clustersecretstore doppler
kubectl get externalsecrets -A
```

Select your cluster first using [cluster access](../operations/cluster-access.md).

For Cloudflare, change `CLOUDFLARE_TUNNEL_TOKEN` in Doppler, wait for the ExternalSecret to refresh successfully, then use Argo CD's **Restart** action on `cloudflared`. For generated autoscaler keys, use the [OpenTofu rotation procedure](../operations/aws-burst-workers.md#rotate-the-autoscaler-key). Updating a Kubernetes Secret does not restart these Deployments automatically.
