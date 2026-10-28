locals {
  secrets = data.doppler_secrets.this.map
}
data "doppler_secrets" "this" {
  project = "talos-proxmox"
  config  = var.env
}

module "generated_secrets" {
  source  = "../secret-contract"
  env     = var.env
  secrets = { KUBECONFIG = { type = "yaml", value = module.proxmox.kubeconfig }, TALOSCONFIG = { type = "yaml", value = module.proxmox.talosconfig } }
}
