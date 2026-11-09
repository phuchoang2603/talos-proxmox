terraform {
  required_version = "< 1.18.0"
  required_providers {
    talos   = { source = "siderolabs/talos", version = "0.12.0" }
    doppler = { source = "DopplerHQ/doppler", version = "1.22.1" }
    proxmox = { source = "bpg/proxmox", version = "0.118.1" }
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    google  = { source = "hashicorp/google", version = "~> 7.0" }
  }
  # Select talos-cluster-dev or talos-cluster-prod with TF_WORKSPACE.
  cloud {
    hostname     = "app.terraform.io"
    organization = "phuchoang2603"
    workspaces {
      tags = ["talos-cluster"]
    }
  }
}

provider "doppler" {}
provider "talos" {}

provider "proxmox" {
  endpoint = var.cloud_provider == "proxmox" ? local.secrets.PROXMOX_ENDPOINT : "https://disabled:8006"
  username = var.cloud_provider == "proxmox" ? local.secrets.PROXMOX_USERNAME : "disabled@pam"
  password = var.cloud_provider == "proxmox" ? local.secrets.PROXMOX_PASSWORD : "disabled"
  insecure = var.proxmox_insecure
  min_tls  = var.proxmox_min_tls
}

provider "google" {
  access_token = var.cloud_provider == "gcp" ? null : "disabled"
  project      = var.gcp_project_id
  region       = var.gcp_region
  zone         = var.gcp_zone
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.cloud_provider == "aws" ? null : "disabled"
  secret_key                  = var.cloud_provider == "aws" ? null : "disabled"
  skip_metadata_api_check     = true
  skip_credentials_validation = var.cloud_provider != "aws"
  skip_requesting_account_id  = var.cloud_provider != "aws"
}
