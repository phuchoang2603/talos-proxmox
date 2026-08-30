# External Secrets Operator - Vault Integration

Bootstrap installs External Secrets and syncs Vault into the cluster (including Longhorn MinIO credentials).

Vault Kubernetes auth is configured **before** Helm bootstrap so ESO can use **client JWT** mode immediately.

## Client JWT mode

- Vault must reach the Kubernetes API at `https://$VIP:6443`
- `disable_local_ca_jwt=true`
- ESO ServiceAccount has `system:auth-delegator` (`apps/manifests/external-secrets-rbac.yaml`)

terraform-admin creates `auth/{env}-kubernetes` and role `external-secrets` bound to SA `external-secrets` in namespace `external-secrets`.

ClusterSecretStores `vault-backend` (env KV) and `vault-shared-backend` (shared KV) are applied from `apps/manifests/external-secrets-cluster-store.yaml.tmpl`.
