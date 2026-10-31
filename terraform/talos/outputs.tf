output "machine_secrets" {
  value     = talos_machine_secrets.this.machine_secrets
  sensitive = true
}
output "client_configuration" {
  value     = talos_machine_secrets.this.client_configuration
  sensitive = true
}
output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}
output "controlplane_configuration" {
  value     = data.talos_machine_configuration.controlplane.machine_configuration
  sensitive = true
}
output "worker_configuration" {
  value     = data.talos_machine_configuration.worker.machine_configuration
  sensitive = true
}
output "controlplane_patches" {
  value = local.controlplane_patches
}
output "common_patches" {
  value = local.common_patches
}
