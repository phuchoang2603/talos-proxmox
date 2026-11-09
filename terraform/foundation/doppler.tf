resource "doppler_project" "this" {
  name = local.doppler_project
}

resource "doppler_environment" "this" {
  for_each = local.environments

  project = doppler_project.this.name
  slug    = each.key
  name    = each.value
}

resource "doppler_service_token" "ci" {
  for_each = doppler_environment.this

  project = doppler_project.this.name
  config  = each.value.slug
  name    = "github-actions"
  access  = "read/write"
}

resource "doppler_service_token" "eso" {
  for_each = doppler_environment.this

  project = doppler_project.this.name
  config  = each.value.slug
  name    = "external-secrets"
  access  = "read"
}

resource "doppler_secret" "eso_token" {
  for_each = doppler_service_token.eso

  project = each.value.project
  config  = each.value.config
  name    = "ESO_DOPPLER_TOKEN"
  value   = each.value.key
}

resource "doppler_service_token" "consumer_eso" {
  for_each = local.consumer_tokens

  project = each.value.project
  config  = each.value.config
  name    = "external-secrets"
  access  = "read"
}

resource "doppler_secret" "consumer_eso_token" {
  for_each = local.consumer_tokens

  project = doppler_project.this.name
  config  = doppler_environment.this[each.value.platform_env].slug
  name    = "ESO_${upper(each.value.key)}_DOPPLER_TOKEN"
  value   = doppler_service_token.consumer_eso[each.key].key
}
