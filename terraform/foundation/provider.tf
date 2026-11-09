terraform {
  required_version = ">= 1.13.2, < 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.22.1"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.82.0"
    }
    minio = {
      source  = "aminueza/minio"
      version = "3.13.2"
    }
  }

  # The organization's default execution mode must be Local before the first init.
  cloud {
    hostname     = "app.terraform.io"
    organization = "phuchoang2603"
    workspaces {
      name = "talos-proxmox"
    }
  }
}

provider "google" {
  access_token = var.cloud_provider == "aws" ? "disabled" : null
  project      = var.gcp_project_id
  region       = var.gcp_region
}

# Authenticates with a workspace-level token from DOPPLER_TOKEN (e.g. `doppler configure get token --plain`).
provider "doppler" {}

# Authenticates with GITHUB_TOKEN (e.g. `gh auth token`).
provider "github" {
  owner = "phuchoang2603"
}

# Authenticates with the `tofu login app.terraform.io` credentials, or TFE_TOKEN.
provider "tfe" {
  organization = local.hcp_organization
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.cloud_provider == "gcp" ? "disabled" : null
  secret_key                  = var.cloud_provider == "gcp" ? "disabled" : null
  skip_metadata_api_check     = true
  skip_credentials_validation = var.cloud_provider == "gcp"
  skip_requesting_account_id  = var.cloud_provider == "gcp"
}

# Dev (Proxmox) object storage runs on an external RustFS endpoint reachable with the
# platform root credentials from Doppler; prod uses GCS and leaves this provider disabled.
provider "minio" {
  minio_server   = var.rustfs_endpoint
  minio_user     = var.cloud_provider == "proxmox" ? data.doppler_secrets.platform_dev[0].map.RUSTFS_ROOT_USER : "disabled"
  minio_password = var.cloud_provider == "proxmox" ? data.doppler_secrets.platform_dev[0].map.RUSTFS_ROOT_PASSWORD : "disabled"
  minio_ssl      = true
  minio_region   = "us-east-1"
}
