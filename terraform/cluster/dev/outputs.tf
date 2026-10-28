output "cluster_name" {
  description = "Talos cluster name"
  value       = module.proxmox.cluster_name
}


output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.proxmox.cluster_endpoint
}


output "talosconfig" {
  description = "talosctl client configuration."
  value       = module.proxmox.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl configuration pointing at the control-plane endpoint"
  value       = module.proxmox.kubeconfig
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs"
  value       = module.proxmox.controlplane_ips
}

output "schematic_id" {
  description = "Talos Image Factory schematic ID (default nodes)"
  value       = module.proxmox.schematic_id
}

output "gpu_schematic_id" {
  description = "Talos Image Factory schematic ID (NVIDIA GPU nodes)"
  value       = module.proxmox.gpu_schematic_id
}
