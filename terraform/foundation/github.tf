locals {
  github_repository = "talos-proxmox"
}

resource "github_repository_environment" "this" {
  for_each = local.environments

  repository  = local.github_repository
  environment = each.key

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  for_each = github_repository_environment.this

  repository     = local.github_repository
  environment    = each.value.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "doppler_token" {
  for_each = github_repository_environment.this

  repository      = local.github_repository
  environment     = each.value.environment
  secret_name     = "DOPPLER_TOKEN"
  plaintext_value = doppler_service_token.ci[each.key].key
}
