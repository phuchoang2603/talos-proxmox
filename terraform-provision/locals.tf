locals {
  network            = jsondecode(file("${path.root}/env/${var.env}/network.json"))
  k8s_nodes_raw      = jsondecode(file("${path.root}/env/${var.env}/k8s_nodes.json"))
  longhorn_nodes_raw = jsondecode(file("${path.root}/env/${var.env}/longhorn_nodes.json"))

  nodes = merge(
    {
      for name, node in local.k8s_nodes_raw : name => {
        role         = node.role
        node         = node.node
        vm_id        = node.vm_id
        address      = node.address
        ip           = split("/", node.address)[0]
        cpu_cores    = var.k8s_cpu_cores
        cpu_type     = var.k8s_cpu_type
        memory_mb    = var.k8s_memory_mb
        datastore_id = var.k8s_datastore_id
        disk_size_gb = var.k8s_disk_size_gb
      }
    },
    {
      for name, node in local.longhorn_nodes_raw : name => {
        role         = node.role
        node         = node.node
        vm_id        = node.vm_id
        address      = node.address
        ip           = split("/", node.address)[0]
        cpu_cores    = var.longhorn_cpu_cores
        cpu_type     = var.longhorn_cpu_type
        memory_mb    = var.longhorn_memory_mb
        datastore_id = var.longhorn_datastore_id
        disk_size_gb = var.longhorn_disk_size_gb
      }
    }
  )
}
