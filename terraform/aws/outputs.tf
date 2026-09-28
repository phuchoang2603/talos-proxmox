output "autoscaling_group_name" {
  value = aws_autoscaling_group.worker.name
}

output "region" {
  value = var.region
}

output "autoscaler_access_key_id" {
  value     = aws_iam_access_key.autoscaler.id
  sensitive = true
}

output "autoscaler_secret_access_key" {
  value     = aws_iam_access_key.autoscaler.secret
  sensitive = true
}
