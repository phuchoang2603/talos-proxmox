resource "talos_machine_secrets" "this" {}

locals {
  controlplane_patch = {
    cluster = {
      apiServer = {
        auditPolicy = yamldecode(file("${path.module}/audit-policy.yaml"))
        extraArgs = {
          "service-account-issuer" = ["https://kubernetes.default.svc.cluster.local", var.cluster_endpoint]
        }
      }
    }
  }
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.controlplane_ips
  nodes                = coalesce(var.controlplane_nodes, var.controlplane_ips)
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [yamlencode(local.controlplane_patch)]
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}
