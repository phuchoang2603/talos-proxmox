# Admin Policy - Full access to environment and shared secrets
resource "vault_policy" "admin_policy" {
  name   = "${var.env}-admin-policy"
  policy = <<-EOT
    # Full access to environment-specific secrets
    path "kv/${var.env}/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Full access to shared secrets
    path "kv/shared/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # List all secret engines
    path "sys/mounts" {
      capabilities = ["read", "list"]
    }

    # Read identity information
    path "identity/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# Developer Policy - Read access to environment and shared secrets
resource "vault_policy" "developer_policy" {
  name   = "${var.env}-developer-policy"
  policy = <<-EOT
    # Read access to environment-specific secrets
    path "kv/${var.env}/data/*" {
      capabilities = ["read", "list"]
    }

    # Cluster-admin Talos/kubectl credentials are admin-only
    path "kv/${var.env}/data/talos" {
      capabilities = ["deny"]
    }

    # Read access to shared secrets
    path "kv/shared/data/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# Create Vault groups for Kubernetes RBAC
resource "vault_identity_group" "kubernetes_admins" {
  name     = "${var.env}-kubernetes-admins"
  type     = "internal"
  policies = [vault_policy.admin_policy.name]

  metadata = {
    environment = var.env
    purpose     = "Vault administrators"
  }
}

resource "vault_identity_group" "kubernetes_developers" {
  name     = "${var.env}-kubernetes-developers"
  type     = "internal"
  policies = [vault_policy.developer_policy.name]

  metadata = {
    environment = var.env
    purpose     = "Vault developers"
  }
}

resource "vault_identity_group" "kubernetes_viewers" {
  name     = "${var.env}-kubernetes-viewers"
  type     = "internal"
  policies = [] # No Vault secret access for viewers

  metadata = {
    environment = var.env
    purpose     = "No Vault secret access"
  }
}
