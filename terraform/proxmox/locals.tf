locals {
  cluster_name       = "${var.env}-talos"
  cluster_endpoint   = "https://${local.bootstrap_ip}:6443"
  controlplane_nodes = { for name, node in var.nodes : name => node if node.role == "servers" }
  worker_nodes       = { for name, node in var.nodes : name => node if node.role == "worker" }
  controlplane_names = sort(keys(local.controlplane_nodes))
  bootstrap_name     = local.controlplane_names[0]
  bootstrap_ip       = local.controlplane_nodes[local.bootstrap_name].ip
  controlplane_ips   = [for name in local.controlplane_names : local.controlplane_nodes[name].ip]
  cert_sans          = local.controlplane_ips
  gpu_nodes          = { for name, node in var.nodes : name => node if length(node.pci) > 0 }

  common_machine_patch = {
    machine = {
      install = {
        disk = var.talos_install_disk
      }
      certSANs = local.cert_sans
      kubelet = {
        # The kubelet sees /var/mnt read-only; local-path needs it writable to create volumes and subPaths.
        extraMounts = [
          {
            destination = "/var/mnt/local-path-provisioner"
            type        = "bind"
            source      = "/var/mnt/local-path-provisioner"
            options     = ["bind", "rshared", "rw"]
          }
        ]
      }
    }
    cluster = {
      apiServer = {
        certSANs = local.cert_sans
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
        nodeLabels = merge(
          node.role == "servers" ? {
            "node.kubernetes.io/exclude-from-external-load-balancers" = {
              "$patch" = "delete"
            }
          } : {},
          contains(keys(local.gpu_nodes), name) ? {
            "nvidia.com/gpu.deploy.device-plugin" = "false"
          } : {}
        )
      }
    })
  }
}
