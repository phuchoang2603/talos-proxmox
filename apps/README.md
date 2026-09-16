# Cluster bootstrap

`bootstrap.sh` installs Cilium (Gateway API, WireGuard encryption, Envoy L7), metrics-server, and Longhorn when any `k8s_nodes.json` entry has `role` `longhorn`. Envs without Longhorn nodes get `local-path-provisioner` as the default StorageClass. The NVIDIA GPU stack installs when any inventory node has a non-empty `pci` list. Argo CD is **argocd only** — see `bootstrap-argocd.sh`.

Per-env Cilium: `values/env/{env}/cilium.yaml` (optional Helm overrides) and `manifests/env/{dev,prod,argocd}/network.yaml` (L2 pool). Longhorn Gateway/HTTPRoute: `longhorn-ingress.yaml` on prod only. Argo CD ingress: `env/argocd/argo-ingress.yaml`.

| | Longhorn | Argo CD |
| --- | --- | --- |
| dev | — | — |
| prod | http://10.69.12.128 | — |
| argocd | — | http://10.69.13.128 |

## bootstrap.sh

Required: `KUBECONFIG`, `ENV_NAME`.

When any node has `role` `longhorn`: `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY`.

Optional chart pins: `CILIUM_VERSION`, `GATEWAY_API_VERSION`, `LONGHORN_VERSION`, `METRICS_SERVER_VERSION`, `GPU_OPERATOR_VERSION`, `NVIDIA_DRA_VERSION`.

## bootstrap-argocd.sh

Run after `bootstrap.sh` with `ENV_NAME=argocd`. Installs Argo CD and registers **dev** and **prod** as remote clusters (kubeconfigs fetched from Doppler via CLI).

Required: `KUBECONFIG`, `ENV_NAME=argocd`, `DOPPLER_READ_TOKEN` (project read token with access to dev and prod configs).

Provision dev and prod before argocd so `KUBECONFIG` exists in each Doppler config.

Optional: `ARGO_CD_VERSION`, `DOPPLER_PROJECT`.
