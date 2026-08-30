# Cluster bootstrap apps

Helm charts and extra manifests applied after Talos is up.

`bootstrap.sh` reads environment variables, renders `*.tmpl` files with `envsubst`, installs Helm releases, then applies manifests.

Required environment:

| Variable | Source |
| --- | --- |
| `KUBECONFIG` | `vault kv get -field=kubeconfig kv/{env}/talos` |
| `ENV_NAME` | `dev` / `prod` |
| `IP_LB_RANGE` | `terraform-provision/env/{env}/network.json` `lb_range` |
| `IP_INGRESS` | same file, `ingress` |
| `SSL_DOMAIN` | Vault Cloudflare `domain` |
| `SSL_API_TOKEN` | Vault Cloudflare `api_token` |
| `SSL_EMAIL` | Vault Cloudflare `email` |
| `VAULT_ADDR` | Vault URL for External Secrets ClusterSecretStore |

Optional: `KUBE_VIP_VERSION` (default `v0.8.0`), `KUBE_VIP_INTERFACE` (default `eth0`).
