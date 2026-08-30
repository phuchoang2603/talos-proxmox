# Repos created after 2026-07-15 use immutable GitHub Actions OIDC subjects:
# repo:OWNER@OWNER_ID/REPO@REPO_ID:...
locals {
  github_oidc_repo = "repo:${var.github_organization}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}"
}

# GitHub Actions Push Role
resource "vault_jwt_auth_backend_role" "github_actions_push_role" {
  backend           = var.jwt_backend_path
  role_name         = "${var.env}-github-actions-push-role"
  role_type         = "jwt"
  token_policies    = [vault_policy.vault_env_policy.name]
  bound_audiences   = ["https://github.com/${var.github_organization}"]
  bound_claims_type = "glob"
  bound_claims = {
    "sub" = "${local.github_oidc_repo}:ref:refs/heads/${var.github_branch}"
  }
  user_claim = "actor"
}

# GitHub Actions PR Role
resource "vault_jwt_auth_backend_role" "github_actions_pr_role" {
  backend           = var.jwt_backend_path
  role_name         = "${var.env}-github-actions-pr-role"
  role_type         = "jwt"
  token_policies    = [vault_policy.vault_env_policy.name]
  bound_audiences   = ["https://github.com/${var.github_organization}"]
  bound_claims_type = "glob"
  bound_claims = {
    "sub" = "${local.github_oidc_repo}:pull_request"
  }
  user_claim = "actor"
}

# Environment-specific Vault Policy
resource "vault_policy" "vault_env_policy" {
  name   = "${var.env}-github-actions-policy"
  policy = <<-EOT
    path "kv/${var.env}/data/*" {
      capabilities = ["read", "list"]
    }

    path "kv/${var.env}/data/talos" {
      capabilities = ["create", "update", "read", "delete"]
    }

    path "kv/${var.env}/metadata/talos" {
      capabilities = ["create", "update", "read", "delete"]
    }

    # Shared policy
    path "kv/shared/data/*" {
      capabilities = ["read", "list"]
    }
    path "kv/shared/metadata/*" {
      capabilities = ["list"]
    }
  EOT
}

