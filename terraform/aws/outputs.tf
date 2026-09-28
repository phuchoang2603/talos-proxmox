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
