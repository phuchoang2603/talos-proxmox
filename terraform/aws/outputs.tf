output "autoscaling_group_name" {
  value = aws_autoscaling_group.worker.name
}

output "region" {
  value = var.region
}
