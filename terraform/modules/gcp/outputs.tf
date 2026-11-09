output "cluster_name" { value = var.cluster_name }
output "cluster_endpoint" { value = "https://${google_compute_address.controlplane.address}:6443" }
output "controlplane_ips" { value = [google_compute_address.controlplane.address] }
output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "kubeconfig" {
  value     = module.bootstrap.kubeconfig
  sensitive = true
}

output "controller_keys" {
  value     = { for name, key in google_service_account_key.controller : name => base64decode(key.private_key) }
  sensitive = true
}

output "autoscaler_groups" {
  value = concat(
    [for name, pool in local.pools : "${pool.min}:${pool.max}:${google_compute_instance_group_manager.worker[name].instance_group}"],
    [for group in google_compute_instance_group_manager.gpu : "1:1:${group.instance_group}"],
  )
}
