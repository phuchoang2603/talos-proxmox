data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_subnet" "worker" {
  id = sort(data.aws_subnets.default.ids)[0]
}

locals {
  name       = "${var.cluster_name}-burst"
  burst_key  = "burst.talos.dev/stateless"
  burst_tag  = "k8s.io/cluster-autoscaler/${var.cluster_name}"
  node_label = "burst.talos.dev/compute"
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = var.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = [
    yamlencode({
      machine = {
        network = {
          kubespan = { enabled = true }
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        nodeLabels = { (local.node_label) = "aws" }
        nodeTaints = { (local.burst_key) = "true:NoSchedule" }
      }
      cluster = {
        discovery = {
          enabled = true
          registries = {
            kubernetes = { disabled = true }
            service    = {}
          }
        }
        network = {
          cni = { name = "none" }
        }
        proxy = { disabled = true }
      }
    }),
  ]
}

resource "aws_security_group" "worker" {
  name_prefix = "${local.name}-"
  description = "Talos KubeSpan burst workers (no public Kubernetes API)"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name       = local.name
    managed-by = "talos-proxmox"
  }
}

resource "aws_vpc_security_group_ingress_rule" "kubespan" {
  security_group_id = aws_security_group.worker.id
  description       = "KubeSpan WireGuard from on-premises peers"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 51820
  to_port           = 51820
  ip_protocol       = "udp"
  tags              = { managed-by = "talos-proxmox" }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { managed-by = "talos-proxmox" }
}

resource "aws_launch_template" "worker" {
  name_prefix   = "${local.name}-"
  image_id      = var.ami_id
  instance_type = "t3.large"
  user_data     = base64encode(data.talos_machine_configuration.worker.machine_configuration)

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.worker.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 40
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  tags = {
    Name       = local.name
    managed-by = "talos-proxmox"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name              = local.name
      managed-by        = "talos-proxmox"
      (local.burst_tag) = "owned"
    }
  }
}

resource "aws_autoscaling_group" "worker" {
  name                = local.name
  vpc_zone_identifier = [data.aws_subnet.worker.id]
  min_size            = 0
  max_size            = 2
  desired_capacity    = 0
  health_check_type   = "EC2"

  launch_template {
    id      = aws_launch_template.worker.id
    version = tostring(aws_launch_template.worker.latest_version)
  }

  dynamic "tag" {
    for_each = {
      "managed-by"                             = "talos-proxmox"
      "k8s.io/cluster-autoscaler/enabled"                                     = "true"
      (local.burst_tag)                                                      = "owned"
      "k8s.io/cluster-autoscaler/node-template/label/${local.node_label}"   = "aws"
      "k8s.io/cluster-autoscaler/node-template/taint/${local.burst_key}"    = "true:NoSchedule"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
