# Shared JWT Auth Backend (used by all environments)
resource "vault_jwt_auth_backend" "jwt" {
  path = "jwt"

  bound_issuer       = "https://token.actions.githubusercontent.com"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
}

# Shared Userpass Auth Backend (used by all environments)
resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
}

# JWT backend for each environment
module "vault_admin" {
  source   = "./modules/vault-jwt"
  for_each = toset(var.environments)

  env                 = each.key
  jwt_backend_path    = vault_jwt_auth_backend.jwt.path
  github_organization  = "phuchoang2603"
  github_repository    = "talos-proxmox"
  github_owner_id      = "91061595"
  github_repository_id = "1351657631"
  github_branch        = "main"
}

# Identity groups and Vault policies (per environment)
module "vault_oidc" {
  source   = "./modules/vault-oidc-kubernetes"
  for_each = toset(var.environments)

  env = each.key
}

# Vault Kubernetes Auth Backend for External Secrets (per environment)
module "vault_k8s_auth" {
  source   = "./modules/vault-kubernetes-auth"
  for_each = toset(var.environments)

  env             = each.key
  kubernetes_host = "https://${jsondecode(file("${path.root}/../terraform-provision/env/${each.key}/network.json")).vip}:6443"
}
