output "cluster_name" {
  value = local.cluster_name
}

output "cluster_endpoint" {
  value = local.cluster_endpoint
}

output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "kubeconfig" {
  value     = module.bootstrap.kubeconfig
  sensitive = true
}

output "controlplane_ips" {
  value = local.controlplane_ips
}

output "schematic_id" {
  value = talos_image_factory_schematic.default.id
}

output "gpu_schematic_id" {
  value = one(talos_image_factory_schematic.gpu[*].id)
}
