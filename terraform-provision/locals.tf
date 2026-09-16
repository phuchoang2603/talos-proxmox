locals {
  network       = jsondecode(file("${path.root}/env/${var.env}/network.json"))
  k8s_nodes_raw = jsondecode(file("${path.root}/env/${var.env}/k8s_nodes.json"))

  nodes = {
    for name, node in local.k8s_nodes_raw : name => {
      role         = node.role
      node         = node.node
      vm_id        = node.vm_id
      address      = node.address
      ip           = split("/", node.address)[0]
      cpu_cores    = node.cpu_cores
      cpu_type     = node.cpu_type
      memory_mb    = node.memory_mb
      datastore_id = node.datastore_id
      disk_size_gb = node.disk_size_gb
      pci          = try(node.pci, [])
    }
  }
}
