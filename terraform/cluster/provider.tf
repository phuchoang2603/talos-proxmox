terraform {
  required_version = ">= 1.12.6, < 1.13.0"
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
  }
  backend "s3" {
    bucket = "terraform"
    region = "us-east-1"
    endpoints = {
      s3 = "http://10.69.1.102:9000"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure
  min_tls  = var.proxmox_min_tls
  username = var.proxmox_username
  password = var.proxmox_password
}

provider "talos" {}


provider "aws" {
  region                      = var.aws_region
  access_key                  = var.env == "argocd" ? "unused" : var.aws_provider_access_key_id
  secret_key                  = var.env == "argocd" ? "unused" : var.aws_provider_secret_access_key
  skip_credentials_validation = var.env == "argocd"
  skip_requesting_account_id  = var.env == "argocd"
  skip_metadata_api_check     = true
}
