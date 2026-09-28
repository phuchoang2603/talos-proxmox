terraform {
  required_version = ">= 1.12.5, < 1.13.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.77.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.21.5"
    }
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

# Authenticates with the environment's config-scoped DOPPLER_TOKEN.
provider "doppler" {}

provider "proxmox" {
  endpoint = local.secrets.PROXMOX_ENDPOINT
  insecure = var.proxmox_insecure
  min_tls  = var.proxmox_min_tls
  username = local.secrets.PROXMOX_USERNAME
  password = local.secrets.PROXMOX_PASSWORD
}

provider "talos" {}

# Uses the ambient AWS session: the GitHub OIDC role in CI, or the operator's session locally.
provider "aws" {
  region                  = var.aws_region
  skip_metadata_api_check = true
}
