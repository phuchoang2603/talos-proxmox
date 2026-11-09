output "cluster_name" {
  description = "Talos cluster name"
  value       = local.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = local.cluster.cluster_endpoint
}

output "talosconfig" {
  description = "talosctl client configuration."
  value       = local.cluster.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl configuration pointing at the control-plane endpoint"
  value       = local.cluster.kubeconfig
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs"
  value       = local.cluster.controlplane_ips
}
