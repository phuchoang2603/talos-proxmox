terraform {
  required_version = ">= 1.13.2, < 1.14.0"
  required_providers {
    talos   = { source = "siderolabs/talos", version = "0.12.0" }
    doppler = { source = "DopplerHQ/doppler", version = "1.22.1" }
    aws     = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  cloud {
    hostname     = "app.terraform.io"
    organization = "phuchoang2603"
    workspaces { name = "talos-cluster-prod" }
  }
}
provider "doppler" {}
provider "talos" {}
provider "aws" {
  region                  = var.aws_region
  skip_metadata_api_check = true
}
