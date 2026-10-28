module "proxmox" {
  source = "../../proxmox"

  env                     = var.env
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
