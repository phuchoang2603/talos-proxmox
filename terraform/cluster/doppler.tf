locals {
  secrets = data.doppler_secrets.this.map

  base_secrets = {
    KUBECONFIG  = { type = "yaml", value = local.cluster.kubeconfig }
    TALOSCONFIG = { type = "yaml", value = local.cluster.talosconfig }
  }

  cloud_secrets = var.cloud_provider == "proxmox" ? {} : {
    AUTOSCALER_CREDENTIALS    = { type = "json", value = var.cloud_provider == "gcp" ? jsonencode({ "key.json" = local.cluster.controller_keys.autoscaler }) : local.cluster.controller_keys.autoscaler }
    BLOCK_STORAGE_CREDENTIALS = { type = "json", value = var.cloud_provider == "gcp" ? jsonencode({ "cloud-sa.json" = local.cluster.controller_keys.pd-csi }) : local.cluster.controller_keys.pd-csi }
    AUTOSCALER_GROUPS         = { type = "json", value = jsonencode(local.cluster.autoscaler_groups) }
    CLOUD_REGION              = { type = "string", value = local.cloud_region }
    CLOUD_ZONE                = { type = "string", value = local.cloud_zone }
    CLOUD_PROJECT_ID          = { type = "string", value = var.cloud_provider == "gcp" ? var.gcp_project_id : "" }
  }
}

data "doppler_secrets" "this" {
  project = var.doppler_project
  config  = coalesce(var.doppler_config, var.env)
}

module "generated_secrets" {
  source  = "./secret-contract"
  project = "talos-proxmox"
  config  = var.env
  secrets = merge(local.base_secrets, local.cloud_secrets)
}
