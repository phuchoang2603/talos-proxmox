terraform {
  required_version = ">= 1.12.5, < 1.13.0"
  required_providers {
    doppler = {
      source  = "DopplerHQ/doppler"
      version = "1.21.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.6.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0"
    }
  }
  # Select talos-platform-dev or talos-platform-prod with TF_WORKSPACE.
  cloud {
    hostname     = "app.terraform.io"
    organization = "phuchoang2603"
    workspaces {
      tags = ["talos-platform"]
    }
  }
}

# Authenticates with the environment's config-scoped DOPPLER_TOKEN.
provider "doppler" {}

provider "kubernetes" {
  host                   = local.kube_cluster.server
  cluster_ca_certificate = base64decode(local.kube_cluster["certificate-authority-data"])
  client_certificate     = base64decode(local.kube_user["client-certificate-data"])
  client_key             = base64decode(local.kube_user["client-key-data"])
}

provider "helm" {
  kubernetes = {
    host                   = local.kube_cluster.server
    cluster_ca_certificate = base64decode(local.kube_cluster["certificate-authority-data"])
    client_certificate     = base64decode(local.kube_user["client-certificate-data"])
    client_key             = base64decode(local.kube_user["client-key-data"])
  }
}

provider "talos" {}
