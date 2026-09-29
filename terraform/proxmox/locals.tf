locals {
  cluster_vip        = var.network.vip
  cluster_name       = "${var.env}-talos"
  cluster_endpoint   = "https://${local.cluster_vip}:6443"
  controlplane_nodes = { for name, node in var.nodes : name => node if node.role == "servers" }
  worker_nodes       = { for name, node in var.nodes : name => node if node.role == "worker" }
  controlplane_names = sort(keys(local.controlplane_nodes))
  bootstrap_name     = local.controlplane_names[0]
  bootstrap_ip       = local.controlplane_nodes[local.bootstrap_name].ip
  controlplane_ips   = [for name in local.controlplane_names : local.controlplane_nodes[name].ip]
  cert_sans          = concat([local.cluster_vip], local.controlplane_ips)
  gpu_nodes          = { for name, node in var.nodes : name => node if length(node.pci) > 0 }

  common_machine_patch = {
    machine = {
      install = {
        disk = var.talos_install_disk
      }
      certSANs = local.cert_sans
      kubelet = {
        extraConfig = {
          systemReserved = {
            cpu    = "250m"
            memory = "1Gi"
          }
          kubeReserved = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
      }
    }
    cluster = {
      allowSchedulingOnControlPlanes = true
      apiServer = {
        certSANs = local.cert_sans
      }
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
    }
  }

  kubespan_machine_patches = [
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
      }
      cluster = {
        discovery = {
          enabled = true
          registries = {
            kubernetes = { disabled = true }
            service    = {}
          }
        }
      }
    }),
  ]

  controlplane_machine_patches = [
    yamlencode({
      machine = {
        features = {
          kubernetesTalosAPIAccess = {
            enabled                     = true
            allowedRoles                = ["os:reader"]
            allowedKubernetesNamespaces = ["kube-system"]
          }
        }
      }
    }),
  ]

  node_machine_patches = {
    for name, node in var.nodes : name => yamlencode({
      machine = {
        install = {
          image = contains(keys(local.gpu_nodes), name) ? one(data.talos_image_factory_urls.gpu[*].urls.installer) : data.talos_image_factory_urls.default.urls.installer
        }
        network = {
          hostname    = name
          nameservers = [var.dns_server]
          interfaces = [
            {
              interface = var.talos_network_interface
              dhcp      = false
              addresses = [node.address]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.vm_ip_gateway
                }
              ]
              vip = node.role == "servers" ? { ip = local.cluster_vip } : null
            }
          ]
        }
        kernel = {
          modules = contains(keys(local.gpu_nodes), name) ? [
            { name = "nvidia" },
            { name = "nvidia_uvm" },
            { name = "nvidia_drm" },
            { name = "nvidia_modeset" },
          ] : []
        }
        nodeLabels = node.role == "servers" ? tomap({
          "node.kubernetes.io/exclude-from-external-load-balancers" = {
            "$patch" = "delete"
          }
        }) : tomap({})
      }
    })
  }
}
