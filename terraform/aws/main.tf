locals {
  tags = {
    managed-by  = "talos-proxmox"
    environment = var.env
  }
  pools = merge({
    cpu = { min = var.worker_min, max = var.worker_max, spot = false }
  }, var.enable_spot ? { spot = { min = 0, max = var.spot_max, spot = true } } : {})
  cloud_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", extraArgs = { "cloud-provider" = "external" } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeTalosAPIAccessConfig", allowedRoles = ["os:reader"], allowedKubernetesNamespaces = ["kube-system"] }),
  ]
}

resource "aws_security_group" "worker" {
  name_prefix = "${var.cluster_name}-"
  description = "Talos cluster nodes"
  vpc_id      = aws_vpc.worker.id
  tags        = local.tags
}
resource "aws_security_group" "controlplane" {
  name_prefix = "${var.cluster_name}-management-"
  description = "Restricted Talos and Kubernetes management"
  vpc_id      = aws_vpc.worker.id
  tags        = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "nodes" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "-1"
  tags                         = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "management" {
  for_each          = { for pair in setproduct(var.management_cidrs, ["6443", "50000"]) : "${pair[0]}:${pair[1]}" => pair }
  security_group_id = aws_security_group.controlplane.id
  cidr_ipv4         = each.value[0]
  from_port         = tonumber(each.value[1])
  to_port           = tonumber(each.value[1])
  ip_protocol       = "tcp"
  tags              = local.tags
}
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = local.tags
}
