# Cluster bootstrap

`bootstrap.sh` installs Cilium, metrics-server, Longhorn, GPU Operator (if `gpu_nodes.json` is non-empty), and Argo CD. Argo CD is a UI only.

Per-env L2 pool and Gateway IPs: `apps/manifests/env/{dev,prod}/network.yaml`. Terraform `network.json` is only `vip` and `lb_range`. Longhorn MinIO credentials come from Vault.

| | Hubble | Longhorn | Argo CD |
| --- | --- | --- | --- |
| dev | http://10.69.100.1 | http://10.69.100.2 | http://10.69.100.3 |
| prod | http://10.69.101.1 | http://10.69.101.2 | http://10.69.101.3 |

Required: `KUBECONFIG`, `ENV_NAME`, `LONGHORN_AWS_ENDPOINTS`, `LONGHORN_AWS_ACCESS_KEY_ID`, `LONGHORN_AWS_SECRET_ACCESS_KEY`.

Optional chart pins: `CILIUM_VERSION`, `GATEWAY_API_VERSION`, `LONGHORN_VERSION`, `METRICS_SERVER_VERSION`, `GPU_OPERATOR_VERSION`, `ARGO_CD_VERSION`.
