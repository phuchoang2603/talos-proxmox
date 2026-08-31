# Cluster bootstrap apps

`bootstrap.sh` Helm-installs Cilium, metrics-server, Longhorn, GPU Operator (when `gpu_nodes.json` is non-empty), and Argo CD. Gateway routes are `kubectl apply`. Argo CD is the UI only — it does not manage the other apps.

LAN IPs are hardcoded in `apps/manifests/env/{dev,prod}/` (`cilium-l2.yaml`, `gateways.yaml`). Terraform `network.json` only has the Talos VIP and Cilium pool range. The Longhorn MinIO secret is written from Vault.

**dev:** Hubble `http://10.69.100.1`, Longhorn `http://10.69.100.2`, Argo CD `http://10.69.100.3`

**prod:** Hubble `http://10.69.101.1`, Longhorn `http://10.69.101.2`, Argo CD `http://10.69.101.3`

Required environment:

| Variable | Source |
| --- | --- |
| `KUBECONFIG` | `vault kv get -field=kubeconfig kv/{env}/talos` |
| `ENV_NAME` | `dev` / `prod` |
| `LONGHORN_AWS_ENDPOINTS` | Vault `kv/shared/minio` `endpoint` |
| `LONGHORN_AWS_ACCESS_KEY_ID` | Vault `kv/shared/minio` `longhorn_a_key` |
| `LONGHORN_AWS_SECRET_ACCESS_KEY` | Vault `kv/shared/minio` `longhorn_s_key` |

Optional: `CILIUM_VERSION` (default `1.18.13`), `GATEWAY_API_VERSION` (default `v1.3.0`), `LONGHORN_VERSION` (default `1.11.1`), `METRICS_SERVER_VERSION` (default `3.14.0`), `GPU_OPERATOR_VERSION` (default `v26.7.0`), `ARGO_CD_VERSION` (default `v9.4.17`).
