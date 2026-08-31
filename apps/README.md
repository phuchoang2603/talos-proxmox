# Cluster bootstrap apps

Helm charts and extra manifests applied after Talos is up.

`bootstrap.sh` reads environment variables, renders `*.tmpl` files with `envsubst`, installs Helm releases, then applies manifests.

Cilium is installed first (Talos ships with CNI and kube-proxy disabled). Nodes stay NotReady until Cilium is running. The Kubernetes API VIP stays on Talos. Cilium L2 announcements cover `Service` type `LoadBalancer`, including the Gateway API listener on `ingress`. Hubble UI is at `hubble.${ENV_NAME}.${SSL_DOMAIN}`.

Required environment:

| Variable | Source |
| --- | --- |
| `KUBECONFIG` | `vault kv get -field=kubeconfig kv/{env}/talos` |
| `ENV_NAME` | `dev` / `prod` |
| `IP_LB_RANGE` | `terraform-provision/env/{env}/network.json` `lb_range` (`start-stop`) |
| `IP_INGRESS` | same file, `ingress` |
| `SSL_DOMAIN` | Vault Cloudflare `domain` |
| `SSL_API_TOKEN` | Vault Cloudflare `api_token` |
| `SSL_EMAIL` | Vault Cloudflare `email` |
| `LONGHORN_AWS_ENDPOINTS` | Vault `kv/shared/minio` `endpoint` |
| `LONGHORN_AWS_ACCESS_KEY_ID` | Vault `kv/shared/minio` `longhorn_a_key` |
| `LONGHORN_AWS_SECRET_ACCESS_KEY` | Vault `kv/shared/minio` `longhorn_s_key` |

Optional: `CILIUM_VERSION` (default `1.18.13`), `CILIUM_INTERFACE` (default `eth0`), `GATEWAY_API_VERSION` (default `v1.3.0`).
