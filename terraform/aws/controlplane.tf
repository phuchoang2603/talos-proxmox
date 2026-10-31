locals {
  cluster_endpoint      = var.create_controlplane ? "https://${aws_eip.controlplane[0].public_ip}:6443" : var.external_cluster.endpoint
  machine_secrets       = var.create_controlplane ? module.talos[0].machine_secrets : var.external_cluster.machine_secrets
  worker_config_patches = var.create_controlplane ? module.talos[0].common_patches : var.external_cluster.worker_config_patches
}
resource "aws_eip" "controlplane" {
  count  = var.create_controlplane ? 1 : 0
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.cluster_name}-api" })
}
module "talos" {
  count              = var.create_controlplane ? 1 : 0
  source             = "../talos"
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  controlplane_ips   = [aws_eip.controlplane[0].public_ip]
  controlplane_nodes = [aws_instance.controlplane[0].private_ip]
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}
data "talos_machine_configuration" "controlplane" {
  count              = var.create_controlplane ? 1 : 0
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = module.talos[0].machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = concat(module.talos[0].common_patches, module.talos[0].controlplane_patches, [
    yamlencode({ machine = { certSANs = [aws_eip.controlplane[0].public_ip] } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", extraArgs = { "cloud-provider" = "external" } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeAPIServerConfig", certExtraSANs = [aws_eip.controlplane[0].public_ip] }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeTalosAPIAccessConfig", allowedRoles = ["os:reader"], allowedKubernetesNamespaces = ["kube-system"] }),
  ])
}
resource "aws_instance" "controlplane" {
  count                       = var.create_controlplane ? 1 : 0
  ami                         = var.ami_id
  instance_type               = var.controlplane_instance_type
  subnet_id                   = aws_subnet.worker[var.availability_zones[0]].id
  vpc_security_group_ids      = [aws_security_group.worker.id]
  iam_instance_profile        = aws_iam_instance_profile.worker.name
  user_data                   = data.talos_machine_configuration.controlplane[0].machine_configuration
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
    ignore_changes = [user_data, ami]
    precondition {
      condition     = length(var.management_cidrs) > 0
      error_message = "Supply operator and current CI egress CIDRs before provisioning the AWS API."
    }
  }
  depends_on = [aws_route.internet, terraform_data.storage_cleanup]
}
resource "aws_eip_association" "controlplane" {
  count         = var.create_controlplane ? 1 : 0
  instance_id   = aws_instance.controlplane[0].id
  allocation_id = aws_eip.controlplane[0].id
}
resource "talos_machine_configuration_apply" "controlplane" {
  count                       = var.create_controlplane ? 1 : 0
  client_configuration        = module.talos[0].client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane[0].machine_configuration
  node                        = aws_instance.controlplane[0].private_ip
  endpoint                    = aws_eip.controlplane[0].public_ip
  depends_on                  = [module.bootstrap]
}
module "bootstrap" {
  count                = var.create_controlplane ? 1 : 0
  source               = "../talos/bootstrap"
  client_configuration = module.talos[0].client_configuration
  endpoint             = aws_eip.controlplane[0].public_ip
  node                 = aws_instance.controlplane[0].private_ip
  depends_on           = [aws_eip_association.controlplane, aws_vpc_security_group_ingress_rule.management]
}
