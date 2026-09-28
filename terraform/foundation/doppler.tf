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
