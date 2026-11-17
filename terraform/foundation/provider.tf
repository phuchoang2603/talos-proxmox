terraform {
  required_version = "< 1.18.0"

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

provider "doppler" {}

provider "github" {
  owner = "phuchoang2603"
}

provider "tfe" {
  organization = local.hcp_organization
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.cloud_provider == "aws" ? null : "disabled"
  secret_key                  = var.cloud_provider == "aws" ? null : "disabled"
  skip_metadata_api_check     = true
  skip_credentials_validation = var.cloud_provider != "aws"
  skip_requesting_account_id  = var.cloud_provider != "aws"
}

provider "minio" {
  minio_server   = var.rustfs_endpoint
  minio_user     = data.doppler_secrets.platform_dev.map.RUSTFS_ROOT_USER
  minio_password = data.doppler_secrets.platform_dev.map.RUSTFS_ROOT_PASSWORD
  minio_ssl      = true
  minio_region   = "us-east-1"
}
