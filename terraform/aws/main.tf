
locals {
  name       = var.cluster_name
  node_label = "burst.talos.dev/compute"
  tags = {
    managed-by  = "talos-proxmox"
    environment = var.env
  }
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = [
    yamlencode(module.talos.common_patch),
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            "cloud-provider"       = "external"
            "node-labels"          = "${local.node_label}=aws"
            "register-with-taints" = "karpenter.sh/unregistered=true:NoExecute"
          }
        }
        network = {
          kubespan = { enabled = false }
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
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
  description = "Talos cluster nodes and restricted management"
  vpc_id      = aws_vpc.worker.id

  tags = merge(local.tags, {
    Name                     = local.name
    "karpenter.sh/discovery" = var.cluster_name
  })
}

resource "aws_vpc_security_group_ingress_rule" "nodes" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "-1"
  tags                         = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "management" {
  for_each          = { for pair in setproduct(var.management_cidrs, ["6443", "50000"]) : "${pair[0]}:${pair[1]}" => pair }
  security_group_id = aws_security_group.worker.id
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
  tags              = { managed-by = "talos-proxmox" }
}
