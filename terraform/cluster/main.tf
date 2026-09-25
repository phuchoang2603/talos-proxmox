module "proxmox" {
  source = "../proxmox"

  env                     = var.env
  network                 = local.network
  nodes                   = local.nodes
  vm_node_name            = var.vm_node_name
  vm_datastore_id         = var.vm_datastore_id
  vm_bridge               = var.vm_bridge
  vm_ip_gateway           = var.vm_ip_gateway
  dns_server              = var.dns_server
  talos_version           = var.talos_version
  kubernetes_version      = var.kubernetes_version
  talos_install_disk      = var.talos_install_disk
  talos_network_interface = var.talos_network_interface
}

module "aws" {
  count  = var.env == "argocd" ? 0 : 1
  source = "../aws"

  env                = var.env
  region             = var.aws_region
  ami_id             = var.aws_ami_id
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  cluster_name       = module.proxmox.cluster_name
  cluster_endpoint   = module.proxmox.cluster_endpoint
  machine_secrets    = module.proxmox.machine_secrets
}
