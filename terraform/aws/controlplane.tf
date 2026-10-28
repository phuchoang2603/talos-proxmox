locals {
  cluster_endpoint = "https://${aws_eip.controlplane.public_ip}:6443"
}
resource "aws_eip" "controlplane" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.cluster_name}-api" })
}
module "talos" {
  source             = "../talos"
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  controlplane_ips   = [aws_eip.controlplane.public_ip]
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = [yamlencode(module.talos.common_patch), yamlencode({
    machine = {
      certSANs = [aws_eip.controlplane.public_ip]
      kubelet  = { extraArgs = { "cloud-provider" = "external" } }
      features = { kubernetesTalosAPIAccess = {
        enabled                     = true
        allowedRoles                = ["os:reader"]
        allowedKubernetesNamespaces = ["kube-system"]
      } }
    }
    cluster = { apiServer = { certSANs = [aws_eip.controlplane.public_ip] } }
  })]
}
resource "aws_instance" "controlplane" {
  ami                         = var.ami_id
  instance_type               = var.controlplane_instance_type
  subnet_id                   = aws_subnet.worker[var.availability_zones[0]].id
  vpc_security_group_ids      = [aws_security_group.worker.id]
  iam_instance_profile        = aws_iam_instance_profile.worker.name
  user_data                   = data.talos_machine_configuration.controlplane.machine_configuration
  user_data_replace_on_change = false
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 40
    encrypted             = true
    delete_on_termination = false
    tags                  = merge(local.tags, { "kubernetes.io/cluster/${var.cluster_name}" = "owned", purpose = "control-plane" })
  }
  tags = merge(local.tags, { Name = "${var.cluster_name}-controlplane", "kubernetes.io/cluster/${var.cluster_name}" = "owned", purpose = "control-plane" })
  lifecycle {
    ignore_changes = [user_data]
    precondition {
      condition     = length(var.management_cidrs) > 0
      error_message = "Supply operator and current CI egress CIDRs before provisioning the AWS API."
    }
  }
  depends_on = [aws_route.internet, terraform_data.storage_cleanup]
}
resource "aws_eip_association" "controlplane" {
  instance_id   = aws_instance.controlplane.id
  allocation_id = aws_eip.controlplane.id
}
resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = module.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = aws_eip.controlplane.public_ip
  endpoint                    = aws_eip.controlplane.public_ip
  depends_on                  = [aws_eip_association.controlplane, aws_vpc_security_group_ingress_rule.management]
}
module "bootstrap" {
  source               = "../talos/bootstrap"
  client_configuration = module.talos.client_configuration
  endpoint             = aws_eip.controlplane.public_ip
  depends_on           = [talos_machine_configuration_apply.controlplane]
}
