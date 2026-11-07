data "aws_ec2_instance_type" "worker" { instance_type = var.worker_machine_type }

data "talos_machine_configuration" "worker" {
  for_each           = local.pools
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${aws_instance.controlplane.private_ip}:6443"
  machine_type       = "worker"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = concat(module.talos.common_patches, local.cloud_patches, [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeNodeConfig", labels = { "talos.dev/nodepool" = each.key, "talos.dev/capacity-type" = each.value.spot ? "spot" : "on-demand" } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", config = { maxPods = 110, shutdownGracePeriod = "25s", shutdownGracePeriodCriticalPods = "5s" } }),
  ])
}
resource "aws_launch_template" "worker" {
  for_each      = local.pools
  name_prefix   = "${var.cluster_name}-${each.key}-"
  image_id      = var.ami_id
  instance_type = var.worker_machine_type
  user_data     = base64encode(data.talos_machine_configuration.worker[each.key].machine_configuration)
  iam_instance_profile { name = aws_iam_instance_profile.worker.name }
  vpc_security_group_ids = [aws_security_group.worker.id]
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 40
      encrypted             = true
      delete_on_termination = true
    }
  }
  dynamic "instance_market_options" {
    for_each = each.value.spot ? [true] : []
    content {
      market_type = "spot"
      spot_options { instance_interruption_behavior = "terminate" }
    }
  }
  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume"])
    content {
      resource_type = tag_specifications.value
      tags          = merge(local.tags, { "kubernetes.io/cluster/${var.cluster_name}" = "owned" })
    }
  }
  tags = local.tags
}
resource "aws_autoscaling_group" "worker" {
  for_each                  = local.pools
  name                      = "${var.cluster_name}-${each.key}"
  min_size                  = each.value.min
  max_size                  = each.value.max
  desired_capacity          = each.value.min
  vpc_zone_identifier       = [aws_subnet.worker[var.zone].id]
  wait_for_capacity_timeout = "0"
  launch_template {
    id      = aws_launch_template.worker[each.key].id
    version = tostring(aws_launch_template.worker[each.key].latest_version)
  }
  dynamic "tag" {
    for_each = merge(local.tags, {
      "kubernetes.io/cluster/${var.cluster_name}"                             = "owned"
      "k8s.io/cluster-autoscaler/enabled"                                     = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}"                         = "owned"
      "k8s.io/cluster-autoscaler/node-template/label/talos.dev/nodepool"      = each.key
      "k8s.io/cluster-autoscaler/node-template/label/talos.dev/capacity-type" = each.value.spot ? "spot" : "on-demand"
      "k8s.io/cluster-autoscaler/node-template/resources/cpu"                 = "${data.aws_ec2_instance_type.worker.default_vcpus * 1000 - 500}m"
      "k8s.io/cluster-autoscaler/node-template/resources/memory"              = "${data.aws_ec2_instance_type.worker.memory_size - 1536}Mi"
      "k8s.io/cluster-autoscaler/node-template/csi-driver"                    = "ebs.csi.aws.com"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  lifecycle { ignore_changes = [desired_capacity] }
  depends_on = [module.bootstrap]
}
