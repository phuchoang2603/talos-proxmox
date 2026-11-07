terraform {
  required_version = ">= 1.13.2, < 1.14.0"
  required_providers {
    talos   = { source = "siderolabs/talos", version = "0.12.0" }
    doppler = { source = "DopplerHQ/doppler", version = "1.22.1" }
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
    google  = { source = "hashicorp/google", version = "~> 7.0" }
    minio   = { source = "aminueza/minio", version = "3.13.2" }
  }
  cloud {
    hostname     = "app.terraform.io"
    organization = "phuchoang2603"
    workspaces { name = "talos-cluster-prod" }
  }
}

provider "doppler" {}
provider "talos" {}
provider "google" {
  access_token = var.cloud_provider == "aws" ? "disabled" : null
  project      = var.gcp_project_id
  region       = var.gcp_region
  zone         = var.gcp_zone
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.cloud_provider == "gcp" ? "disabled" : null
  secret_key                  = var.cloud_provider == "gcp" ? "disabled" : null
  skip_metadata_api_check     = true
  skip_credentials_validation = var.cloud_provider == "gcp"
  skip_requesting_account_id  = var.cloud_provider == "gcp"
}
