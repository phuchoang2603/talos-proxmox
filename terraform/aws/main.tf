
locals {
  name       = "${var.cluster_name}-burst"
  burst_key  = "burst.talos.dev/stateless"
  node_label = "burst.talos.dev/compute"
  tags = {
    managed-by  = "talos-proxmox"
    environment = var.env
  }
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
        kubelet = {
          extraArgs = {
            "cloud-provider"       = "external"
            "node-labels"          = "${local.node_label}=aws"
            "register-with-taints" = "${local.burst_key}=true:NoSchedule,karpenter.sh/unregistered=true:NoExecute"
          }
        }
        network = {
          kubespan = { enabled = true }
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
  description = "Talos KubeSpan burst workers (no public Kubernetes API)"
  vpc_id      = aws_vpc.worker.id

  tags = merge(local.tags, {
    Name                     = local.name
    "karpenter.sh/discovery" = var.cluster_name
  })
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
