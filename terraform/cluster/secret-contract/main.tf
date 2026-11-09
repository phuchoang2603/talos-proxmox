terraform {
  required_providers {
    doppler = { source = "DopplerHQ/doppler" }
  }
}

variable "project" {
  type    = string
  default = "talos-proxmox"
}
variable "config" { type = string }
variable "secrets" {
  type      = map(object({ type = string, value = string }))
  sensitive = true
}

resource "doppler_secret" "generated" {
  for_each   = nonsensitive(toset(keys(var.secrets)))
  project    = var.project
  config     = var.config
  name       = each.key
  value      = var.secrets[each.key].value
  value_type = var.secrets[each.key].type
}
