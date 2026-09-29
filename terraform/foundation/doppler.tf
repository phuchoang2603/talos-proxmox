import {
  to = doppler_project.this
  id = local.doppler_project
}

resource "doppler_project" "this" {
  name = local.doppler_project
}

import {
  for_each = local.environments
  to       = doppler_environment.this[each.key]
  id       = "${local.doppler_project}.${each.key}"
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

resource "random_password" "otel_ingest_token" {
  length  = 48
  special = false
}

resource "doppler_secret" "otel_ingest_token" {
  for_each = doppler_environment.this

  project = doppler_project.this.name
  config  = each.value.slug
  name    = "OTEL_INGEST_TOKEN"
  value   = random_password.otel_ingest_token.result
}

resource "random_password" "observability" {
  for_each = toset([
    "CLICKHOUSE_DEFAULT_PASSWORD",
    "CLICKHOUSE_OTEL_PASSWORD",
    "CLICKHOUSE_APP_PASSWORD",
    "HYPERDX_MONGODB_PASSWORD",
  ])

  length  = 32
  special = false
}

resource "random_uuid" "hyperdx_api_key" {}

resource "doppler_secret" "observability" {
  for_each = merge(
    { for name, password in random_password.observability : name => password.result },
    { HYPERDX_API_KEY = random_uuid.hyperdx_api_key.result },
  )

  project = doppler_project.this.name
  config  = doppler_environment.this["prod"].slug
  name    = each.key
  value   = each.value
}
