module "talos" {
  source                 = "../talos"
  cluster_name           = local.cluster_name
  service_account_issuer = var.service_account_issuer
  controlplane_ips       = local.controlplane_ips
}
