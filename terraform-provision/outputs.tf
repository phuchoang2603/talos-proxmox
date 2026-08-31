output "cluster_name" {
  description = "Talos cluster name"
  value       = module.talos.cluster_name
}

output "cluster_vip" {
  description = "Kubernetes API virtual IP"
  value       = module.talos.cluster_vip
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (VIP)"
  value       = module.talos.cluster_endpoint
}

output "lb_range" {
  description = "Cilium LoadBalancer IP range (L2 announcements)"
  value       = module.talos.lb_range
}

output "ingress_ip" {
  description = "Traefik LoadBalancer IP"
  value       = module.talos.ingress_ip
}

output "talosconfig" {
  description = "talosctl client configuration. Endpoints are node IPs, not the VIP."
  value       = module.talos.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl configuration pointing at the control-plane VIP"
  value       = module.talos.kubeconfig
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs (use these with talosctl, not the VIP)"
  value       = module.talos.controlplane_ips
}

output "schematic_id" {
  description = "Talos Image Factory schematic ID (default nodes)"
  value       = module.talos.schematic_id
}

output "gpu_schematic_id" {
  description = "Talos Image Factory schematic ID (NVIDIA GPU nodes)"
  value       = module.talos.gpu_schematic_id
}
