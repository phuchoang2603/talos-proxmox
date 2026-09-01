# Cluster bootstrap

`bootstrap.sh` installs Cilium (Gateway API, WireGuard encryption, Envoy L7), metrics-server, and Longhorn when `longhorn_nodes.json` is non-empty. The NVIDIA GPU stack installs when `gpu_nodes.json` is non-empty. Argo CD and External Secrets Operator are **gpu only** — see `bootstrap-gpu.sh`.

Per-env Cilium L2 pool: `apps/manifests/env/{dev,prod,gpu}/network.yaml`. Longhorn Gateway/HTTPRoute: `longhorn-ingress.yaml` on prod/gpu only. Gpu-only: `env/gpu/doppler.yaml` (ESO stores), `env/gpu/argo-ingress.yaml`.

| | Longhorn | Argo CD |
| --- | --- | --- |
| dev | — | — |
| prod | http://10.69.101.2 | — |
| gpu | http://10.69.102.2 | http://10.69.102.3 |

## bootstrap.sh

Required: `KUBECONFIG`, `ENV_NAME`.

When `longhorn_nodes.json` has nodes: `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY`.

Optional chart pins: `CILIUM_VERSION`, `GATEWAY_API_VERSION`, `LONGHORN_VERSION`, `METRICS_SERVER_VERSION`, `GPU_OPERATOR_VERSION`, `NVIDIA_DRA_VERSION`.

## bootstrap-gpu.sh

Run after `bootstrap.sh` with `ENV_NAME=gpu`. Installs External Secrets Operator, Doppler `ClusterSecretStore`s (`doppler-dev`, `doppler-prod`, `doppler-gpu`), Argo CD, and registers **dev** and **prod** as remote clusters.

Required: `KUBECONFIG`, `ENV_NAME=gpu`, `DOPPLER_READ_TOKEN` (project read token with access to dev, prod, and gpu configs — used in-cluster by ESO and by this script to fetch remote kubeconfigs).

Provision dev and prod before gpu so `KUBECONFIG` exists in each Doppler config.

Optional: `ARGO_CD_VERSION`, `EXTERNAL_SECRETS_VERSION`, `DOPPLER_PROJECT`.

Example `ExternalSecret` using the gpu store:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secret
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: doppler-gpu
    kind: ClusterSecretStore
  target:
    name: my-app-secret
  data:
    - secretKey: api-key
      remoteRef:
        key: MY_DOPPLER_SECRET
```

Use `doppler-dev`, `doppler-prod`, or `doppler-gpu` as the store name (all backed by the same `DOPPLER_READ_TOKEN` in-cluster).
