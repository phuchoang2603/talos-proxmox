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
output "controlplane_patch" {
  value = local.controlplane_patch
}
output "common_patch" {
  value = {
    machine = {
      features = { kubePrism = { enabled = true, port = 7445 } }
      kubelet = {
        extraConfig = {
          systemReserved = { cpu = "250m", memory = "1Gi" }
          kubeReserved   = { cpu = "250m", memory = "512Mi" }
        }
      }
    }
    cluster = {
      allowSchedulingOnControlPlanes = true
      network                        = { cni = { name = "none" } }
      proxy                          = { disabled = true }
    }
  }
}
