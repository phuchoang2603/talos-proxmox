terraform {
  required_version = ">= 1.13.2, < 1.14.0"
  required_providers {
    talos   = { source = "siderolabs/talos", version = "0.12.0" }
    doppler = { source = "DopplerHQ/doppler", version = "1.22.1" }
    proxmox = { source = "bpg/proxmox", version = "0.118.1" }
  }
  cloud {
    hostname     = "app.terraform.io"
    organization = "phuchoang2603"
    workspaces { name = "talos-cluster-dev" }
  }
}
provider "doppler" {}
provider "talos" {}
provider "proxmox" {
  endpoint = local.secrets.PROXMOX_ENDPOINT
  username = local.secrets.PROXMOX_USERNAME
  password = local.secrets.PROXMOX_PASSWORD
  insecure = var.proxmox_insecure
  min_tls  = var.proxmox_min_tls
}
