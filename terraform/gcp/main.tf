terraform {
  required_providers {
    google = { source = "hashicorp/google" }
    talos  = { source = "siderolabs/talos" }
  }
}

locals {
  tags = [var.cluster_name]
  pools = merge({
    cpu = { min = var.worker_min, max = var.worker_max, spot = false }
  }, var.enable_spot ? { spot = { min = 0, max = var.spot_max, spot = true } } : {})
  cloud_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", extraArgs = { "cloud-provider" = "external" } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeTalosAPIAccessConfig", allowedRoles = ["os:reader"], allowedKubernetesNamespaces = ["kube-system"] }),
  ]
}

resource "google_service_account" "node" {
  account_id   = "${var.cluster_name}-node"
  display_name = "Talos nodes without application permissions"
}
