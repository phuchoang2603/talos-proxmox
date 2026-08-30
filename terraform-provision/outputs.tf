output "cluster_name" {
  description = "Talos cluster name"
  value       = local.cluster_name
}

output "cluster_vip" {
  description = "Kubernetes API virtual IP"
  value       = local.cluster_vip
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (VIP)"
  value       = local.cluster_endpoint
}

output "lb_range" {
  description = "kube-vip LoadBalancer IP range"
  value       = local.network.lb_range
}

output "ingress_ip" {
  description = "Traefik LoadBalancer IP"
  value       = local.network.ingress
}

output "talosconfig" {
  description = "talosctl client configuration. Endpoints are node IPs, not the VIP."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "kubectl configuration pointing at the control-plane VIP"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "controlplane_ips" {
  description = "Control plane node IPs (use these with talosctl, not the VIP)"
  value       = local.controlplane_ips
}

output "schematic_id" {
  description = "Talos Image Factory schematic ID"
  value       = talos_image_factory_schematic.this.id
}
