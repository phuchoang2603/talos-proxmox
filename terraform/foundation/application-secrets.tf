locals {
  application_passwords = toset(["AUTH_DEX_PASSWORD", "AUTH_OIDC_CLIENT_SECRET", "OPENMETADATA_OIDC_CLIENT_SECRET", "OPENMETADATA_POSTGRES_PASSWORD", "KUBEFLOW_KFP_POSTGRES_PASSWORD", "KUBEFLOW_KATIB_POSTGRES_PASSWORD", "KUBEFLOW_CATALOG_POSTGRES_PASSWORD", "STARROCKS_ROOT_PASSWORD", "STARROCKS_OPENMETADATA_PASSWORD", "ICEBERG_POSTGRES_PASSWORD", "ICEBERG_CLIENT_SECRET", "KAGENT_POSTGRES_PASSWORD", "AGENTREGISTRY_POSTGRES_PASSWORD"])
  environment_passwords = { for pair in setproduct(keys(local.environments), local.application_passwords) : "${pair[0]}/${pair[1]}" => { env = pair[0], name = pair[1] } }
  generated_application_secrets = merge(
    { for key, password in random_password.application : key => { env = local.environment_passwords[key].env, name = local.environment_passwords[key].name, value = password.result } },
    merge([for env in keys(local.environments) : {
      "${env}/AUTH_DEX_PASSWORD_BCRYPT"         = { env = env, name = "AUTH_DEX_PASSWORD_BCRYPT", value = random_password.application["${env}/AUTH_DEX_PASSWORD"].bcrypt_hash }
      "${env}/AUTH_OAUTH2_COOKIE_SECRET"        = { env = env, name = "AUTH_OAUTH2_COOKIE_SECRET", value = random_id.cookie[env].b64_std }
      "${env}/OPENMETADATA_FERNET_KEY"          = { env = env, name = "OPENMETADATA_FERNET_KEY", value = replace(replace(random_id.fernet[env].b64_std, "+", "-"), "/", "_") }
      "${env}/OPENMETADATA_RSA_PRIVATE_KEY_DER" = { env = env, name = "OPENMETADATA_RSA_PRIVATE_KEY_DER", value = replace(replace(replace(tls_private_key.signing[env].private_key_pem_pkcs8, "-----BEGIN PRIVATE KEY-----", ""), "-----END PRIVATE KEY-----", ""), "\n", "") }
      "${env}/OPENMETADATA_RSA_PUBLIC_KEY_DER"  = { env = env, name = "OPENMETADATA_RSA_PUBLIC_KEY_DER", value = replace(replace(replace(tls_private_key.signing[env].public_key_pem, "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", "") }
      "${env}/ICEBERG_TOKEN_PRIVATE_KEY"        = { env = env, name = "ICEBERG_TOKEN_PRIVATE_KEY", value = tls_private_key.iceberg[env].private_key_pem_pkcs8 }
      "${env}/ICEBERG_TOKEN_PUBLIC_KEY"         = { env = env, name = "ICEBERG_TOKEN_PUBLIC_KEY", value = tls_private_key.iceberg[env].public_key_pem }
    }]...)
  )
}
locals {
  application_secrets = {
    for key, secret in local.generated_application_secrets : key => merge(secret, {
      value = try(var.operator_secrets[secret.env][secret.name], secret.value)
    })
  }
}
resource "random_password" "application" {
  for_each = local.environment_passwords
  length   = 32
  special  = false
}
resource "random_id" "cookie" {
  for_each    = local.environments
  byte_length = 32
}
resource "random_id" "fernet" {
  for_each    = local.environments
  byte_length = 32
}
resource "tls_private_key" "signing" {
  for_each  = local.environments
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "tls_private_key" "iceberg" {
  for_each  = local.environments
  algorithm = "RSA"
  rsa_bits  = 2048
}
resource "doppler_secret" "application" {
  for_each = nonsensitive(toset(keys(local.application_secrets)))
  project  = doppler_project.this.name
  config   = doppler_environment.this[local.application_secrets[each.key].env].slug
  name     = local.application_secrets[each.key].name
  value    = local.application_secrets[each.key].value
}
variable "operator_secrets" {
  type      = map(map(string))
  sensitive = true
}
locals {
  operator_secrets = merge([for env, secrets in var.operator_secrets : {
    for name, value in secrets : "${env}/${name}" => { env = env, name = name, value = value } if !contains(keys(local.generated_application_secrets), "${env}/${name}")
  }]...)
}
resource "doppler_secret" "operator" {
  for_each = nonsensitive(toset(keys(local.operator_secrets)))
  project  = doppler_project.this.name
  config   = doppler_environment.this[local.operator_secrets[each.key].env].slug
  name     = local.operator_secrets[each.key].name
  value    = local.operator_secrets[each.key].value
}
