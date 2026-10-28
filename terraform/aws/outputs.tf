output "worker_machine_configuration" {
  description = "Talos worker machine configuration Karpenter passes to launched instances as user data"
  value       = data.talos_machine_configuration.worker.machine_configuration
  sensitive   = true
}

output "worker_ami_id" {
  value = var.ami_id
}

output "worker_instance_profile" {
  value = aws_iam_instance_profile.worker.name
}

output "region" {
  value = var.region
}

output "karpenter_access_key_id" {
  value     = aws_iam_access_key.karpenter.id
  sensitive = true
}

output "karpenter_secret_access_key" {
  value     = aws_iam_access_key.karpenter.secret
  sensitive = true
}

output "gpu_worker_machine_configuration" {
  description = "Talos GPU worker machine configuration, empty until gpu_ami_id is set"
  value       = one(data.talos_machine_configuration.worker_gpu[*].machine_configuration)
  sensitive   = true
}


output "gpu_schematic_id" {
  value = talos_image_factory_schematic.gpu.id
}

output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "cluster_name" { value = var.cluster_name }
output "cluster_endpoint" { value = local.cluster_endpoint }
output "controlplane_ips" { value = [aws_eip.controlplane.public_ip] }
output "schematic_id" { value = null }
output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}
output "kubeconfig" {
  value     = module.bootstrap.kubeconfig
  sensitive = true
}
output "interruption_queue" { value = aws_sqs_queue.interruption.name }
