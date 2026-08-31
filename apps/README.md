# Cluster bootstrap apps

Cilium (CNI) and Argo CD are installed by `bootstrap.sh`. Everything else is an Argo CD Application pointing at this repo.

Bootstrap still writes the Longhorn MinIO secret from Vault. LAN IPs are hardcoded in `apps/gitops/{dev,prod}/` and `apps/manifests/env/{dev,prod}/cilium-l2.yaml`.

**dev:** Hubble `http://10.69.100.1`, Longhorn `http://10.69.100.2`, Argo CD `http://10.69.100.3`

Required environment:

| Variable | Source |
| --- | --- |
| `KUBECONFIG` | `vault kv get -field=kubeconfig kv/{env}/talos` |
| `ENV_NAME` | `dev` / `prod` |
| `LONGHORN_AWS_ENDPOINTS` | Vault `kv/shared/minio` `endpoint` |
| `LONGHORN_AWS_ACCESS_KEY_ID` | Vault `kv/shared/minio` `longhorn_a_key` |
| `LONGHORN_AWS_SECRET_ACCESS_KEY` | Vault `kv/shared/minio` `longhorn_s_key` |

Optional: `CILIUM_VERSION` (default `1.18.13`), `GATEWAY_API_VERSION` (default `v1.3.0`).
