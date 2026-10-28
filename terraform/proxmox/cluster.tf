module "talos" {
  source             = "../talos"
  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  controlplane_ips   = local.controlplane_ips
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}
