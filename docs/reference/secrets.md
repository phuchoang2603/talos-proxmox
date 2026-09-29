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

## Generated secrets

| Doppler key | Writer | Consumer |
| --- | --- | --- |
| `ESO_DOPPLER_TOKEN` | Foundation | Platform creates `kube-system/doppler-token` |
| `KUBECONFIG` | Cluster root | Platform providers and operators |
| `TALOSCONFIG` | Cluster root | Operators using `talosctl` |
| `KARPENTER_AWS_ACCESS_KEY_ID`, `KARPENTER_AWS_SECRET_ACCESS_KEY` | Cluster root's AWS module | Platform creates `kube-system/karpenter-aws` |
| `AWS_WORKER_MACHINE_CONFIG`, `AWS_WORKER_AMI_ID` | Cluster root's AWS module | Platform passes them to the Karpenter `EC2NodeClass` |

Foundation also creates a read/write CI service token per config and publishes it as that GitHub Environment's `DOPPLER_TOKEN` secret. This differs from the read-only ESO token. A local foundation apply uses a workspace-level Doppler login token to manage these service tokens.

## Credential boundaries

| Credential | Scope/use |
| --- | --- |
| CI Doppler token | Read/write one environment config |
| ESO Doppler token | Read one environment config; only Doppler credential installed in the cluster |
| CI AWS session | GitHub OIDC provisioning role |
| Karpenter AWS key | Launch, tag, and terminate the environment's tagged instances; regional Describe access |
| HCP operator token | State access across the configured workspaces |

HCP state holds generated credentials and Talos bootstrap material. Doppler provider reads also bring secret data into the planning/state flow. Keep state and saved plans restricted to operators; sensitive plan rendering is not encryption of state.

## Delivery and rotation

| Kubernetes Secret | Namespace | Refresh |
| --- | --- | --- |
| `cloudflare-tunnel-token` | `cloudflare-tunnel` | 1 hour |

It is produced by an ExternalSecret using the `doppler` ClusterSecretStore. If Doppler is unreachable, existing Secrets are retained and refresh failures are exposed through ESO status. Inspect status without printing secret values:

```bash
kubectl get clustersecretstore doppler
kubectl get externalsecrets -A
```

Select your cluster first using [cluster access](../operations/cluster-access.md).

For Cloudflare, change `CLOUDFLARE_TUNNEL_TOKEN` in Doppler, wait for the ExternalSecret to refresh successfully, then use Argo CD's **Restart** action on `cloudflared`. Updating a Kubernetes Secret does not restart these Deployments automatically. The Karpenter key is not delivered by ESO: rotate it with the [OpenTofu procedure](../operations/aws-burst-workers.md#rotate-the-karpenter-key), where the platform apply restarts the controller.
