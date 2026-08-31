locals {
  cluster_vip        = var.network.vip
  cluster_name       = "${var.env}-talos"
  cluster_endpoint   = "https://${local.cluster_vip}:6443"
  controlplane_nodes = { for name, node in var.nodes : name => node if node.role == "servers" }
  worker_nodes       = { for name, node in var.nodes : name => node if node.role != "servers" }
  controlplane_names = sort(keys(local.controlplane_nodes))
  bootstrap_name     = local.controlplane_names[0]
  bootstrap_ip       = local.controlplane_nodes[local.bootstrap_name].ip
  controlplane_ips   = [for name in local.controlplane_names : local.controlplane_nodes[name].ip]
  cert_sans          = concat([local.cluster_vip], local.controlplane_ips)
  gpu_nodes          = { for name, node in var.nodes : name => node if node.role == "gpu" || length(node.pci) > 0 }

  common_machine_patch = {
    machine = {
      install = {
        disk = var.talos_install_disk
      }
      certSANs = local.cert_sans
      kernel = {
        modules = [
          { name = "iscsi_tcp" },
          { name = "dm_crypt" },
        ]
      }
      kubelet = {
        extraMounts = [
          {
            destination = "/var/lib/longhorn"
            type        = "bind"
            source      = "/var/lib/longhorn"
            options     = ["bind", "rshared", "rw"]
          }
        ]
      }
    }
    cluster = {
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

  node_machine_patches = {
    for name, node in var.nodes : name => yamlencode({
      machine = {
        install = {
          image = contains(keys(local.gpu_nodes), name) ? data.talos_image_factory_urls.gpu.urls.installer : data.talos_image_factory_urls.default.urls.installer
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
          modules = concat(
            [
              { name = "iscsi_tcp" },
              { name = "dm_crypt" },
            ],
            contains(keys(local.gpu_nodes), name) ? [
              { name = "nvidia" },
              { name = "nvidia_uvm" },
              { name = "nvidia_drm" },
              { name = "nvidia_modeset" },
            ] : []
          )
        }
        nodeLabels = merge(
          node.role == "longhorn" ? tomap({ "node.longhorn.io/create-default-disk" = "true" }) : tomap({}),
          contains(keys(local.gpu_nodes), name) ? tomap({ "nvidia.com/gpu.present" = "true" }) : tomap({}),
        )
      }
    })
  }
}
