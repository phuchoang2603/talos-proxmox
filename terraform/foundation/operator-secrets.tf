locals {
  operator_secret_names = toset([
    "HCP_TERRAFORM_TOKEN",
    "CLOUD_MANAGEMENT_CIDRS",
    "PROXMOX_ENDPOINT",
    "PROXMOX_USERNAME",
    "PROXMOX_PASSWORD",
    "TS_OAUTH_CLIENT_ID",
    "TS_OAUTH_SECRET",
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_TUNNEL_TOKEN",
  ])
  operator_secrets = merge([for env, secrets in var.operator_secrets : {
    for name, value in secrets : "${env}/${name}" => { env = env, name = name, value = value } if contains(local.operator_secret_names, name)
  }]...)
}

resource "doppler_secret" "operator" {
  for_each = nonsensitive(toset(keys(local.operator_secrets)))
  project  = doppler_project.this.name
  config   = doppler_environment.this[local.operator_secrets[each.key].env].slug
  name     = local.operator_secrets[each.key].name
  value    = local.operator_secrets[each.key].value
}
