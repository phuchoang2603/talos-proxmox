output "cluster_name" {
  value = local.cluster_name
}

output "cluster_vip" {
  value = local.cluster_vip
}

output "cluster_endpoint" {
  value = local.cluster_endpoint
}

output "lb_range" {
  value = var.network.lb_range
}

output "ingress_ip" {
  value = var.network.ingress
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "controlplane_ips" {
  value = local.controlplane_ips
}

output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}
