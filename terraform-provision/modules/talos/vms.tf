module "nodes" {
  source = "../vm"

  for_each = var.nodes

  name         = each.key
  node_name    = each.value.node
  vm_id        = each.value.vm_id
  cpu_cores    = each.value.cpu_cores
  cpu_type     = each.value.cpu_type
  memory_mb    = each.value.memory_mb
  datastore_id = each.value.datastore_id
  disk_file_id = contains(keys(local.gpu_nodes), each.key) ? proxmox_virtual_environment_download_file.talos_gpu_image.id : proxmox_virtual_environment_download_file.talos_image.id
  disk_size_gb = each.value.disk_size_gb
  bridge       = var.vm_bridge
  dns_server   = var.dns_server
  ip_address   = each.value.address
  ip_gateway   = var.vm_ip_gateway
  pci          = each.value.pci
}
