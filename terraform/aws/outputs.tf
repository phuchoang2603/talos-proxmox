output "cluster_name" { value = var.cluster_name }
output "cluster_endpoint" { value = local.cluster_endpoint }
output "controlplane_ips" { value = [aws_eip.controlplane.public_ip] }
output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}
output "kubeconfig" {
  value     = module.bootstrap.kubeconfig
  sensitive = true
}
output "controller_keys" {
  value = {
    autoscaler = jsonencode({ AWS_ACCESS_KEY_ID = aws_iam_access_key.autoscaler.id, AWS_SECRET_ACCESS_KEY = aws_iam_access_key.autoscaler.secret })
    pd-csi     = jsonencode({ AWS_ACCESS_KEY_ID = aws_iam_access_key.ebs.id, AWS_SECRET_ACCESS_KEY = aws_iam_access_key.ebs.secret })
  }
  sensitive = true
}
output "autoscaler_groups" {
  value = [for name, pool in local.pools : "${pool.min}:${pool.max}:${aws_autoscaling_group.worker[name].name}"]
}
