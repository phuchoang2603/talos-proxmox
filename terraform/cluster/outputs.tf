output "cluster_name" {
  description = "Talos cluster name"
  value       = module.proxmox.cluster_name
}

output "cluster_vip" {
  description = "Kubernetes API virtual IP"
  value       = module.proxmox.cluster_vip
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (VIP)"
  value       = module.proxmox.cluster_endpoint
}

output "lb_range" {
  description = "Cilium LoadBalancer IP range (L2 announcements)"
  value       = module.proxmox.lb_range
}

output "talosconfig" {
  description = "talosctl client configuration. Endpoints are node IPs, not the VIP."
  value       = module.proxmox.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl configuration pointing at the control-plane VIP"
  value       = module.proxmox.kubeconfig
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs (use these with talosctl, not the VIP)"
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
