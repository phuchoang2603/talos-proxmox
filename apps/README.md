# Cluster bootstrap

`bootstrap.sh` installs Cilium (Gateway API, Hubble, WireGuard encryption, Envoy L7), metrics-server, Longhorn, GPU Operator plus the NVIDIA DRA driver (if `gpu_nodes.json` is non-empty), and Argo CD. Argo CD is a UI only. GPU access is DRA (`nvidia-dra-driver-gpu`), not the device plugin.

Per-env Cilium L2 pool, Hubble Gateway, and routes: `apps/manifests/env/{dev,prod,gpu}/network.yaml` (`kube-system`). Longhorn and Argo Gateway/HTTPRoute live in `longhorn-ingress.yaml` and `argo-ingress.yaml` under the same env folder (`longhorn-system`, `argo-cd`). Terraform `network.json` is only `vip` and `lb_range`. Longhorn MinIO credentials stay in `longhorn-system`.

| | Hubble | Longhorn | Argo CD |
| --- | --- | --- | --- |
| dev | http://10.69.1.113 | http://10.69.1.114 | http://10.69.1.115 |
| prod | http://10.69.101.1 | http://10.69.101.2 | http://10.69.101.3 |
| gpu | http://10.69.102.1 | http://10.69.102.2 | http://10.69.102.3 |

Required: `KUBECONFIG`, `ENV_NAME`, `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY`.

Optional chart pins: `CILIUM_VERSION`, `GATEWAY_API_VERSION`, `LONGHORN_VERSION`, `METRICS_SERVER_VERSION`, `GPU_OPERATOR_VERSION`, `NVIDIA_DRA_VERSION`, `ARGO_CD_VERSION`.
