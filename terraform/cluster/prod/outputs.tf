output "cluster_name" {
  description = "Talos cluster name"
  value       = module.aws.cluster_name
}


output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.aws.cluster_endpoint
}


output "talosconfig" {
  description = "talosctl client configuration."
  value       = module.aws.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl configuration pointing at the control-plane endpoint"
  value       = module.aws.kubeconfig
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs"
  value       = module.aws.controlplane_ips
}

output "schematic_id" {
  description = "Talos Image Factory schematic ID (default nodes)"
  value       = module.aws.schematic_id
}

output "gpu_schematic_id" {
  description = "Talos Image Factory schematic ID (NVIDIA GPU nodes)"
  value       = module.aws.gpu_schematic_id
}
