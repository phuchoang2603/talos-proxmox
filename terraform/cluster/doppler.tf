locals {
  doppler_project = "talos-proxmox"
  secrets         = data.doppler_secrets.this.map

  generated_secret_types = {
    KUBECONFIG                       = "yaml"
    TALOSCONFIG                      = "yaml"
    AUTOSCALER_AWS_ACCESS_KEY_ID     = "string"
    AUTOSCALER_AWS_SECRET_ACCESS_KEY = "string"
  }

  generated_secret_values = {
    KUBECONFIG                       = module.proxmox.kubeconfig
    TALOSCONFIG                      = module.proxmox.talosconfig
    AUTOSCALER_AWS_ACCESS_KEY_ID     = module.aws.autoscaler_access_key_id
    AUTOSCALER_AWS_SECRET_ACCESS_KEY = module.aws.autoscaler_secret_access_key
  }
}

data "doppler_secrets" "this" {
  project = local.doppler_project
  config  = var.env
}

resource "doppler_secret" "generated" {
  for_each = local.generated_secret_types

  project    = local.doppler_project
  config     = var.env
  name       = each.key
  value      = local.generated_secret_values[each.key]
  value_type = each.value
}
