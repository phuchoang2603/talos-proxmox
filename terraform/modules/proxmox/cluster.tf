module "talos" {
  source           = "../talos"
  cluster_name     = local.cluster_name
  controlplane_ips = local.controlplane_ips
}
