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

  common_machine_patch = {
    machine = {
      install = {
        disk  = var.talos_install_disk
        image = data.talos_image_factory_urls.this.urls.installer
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
      proxy = {
        extraArgs = {
          "proxy-mode"      = "ipvs"
          "ipvs-strict-arp" = "true"
        }
      }
    }
  }

  node_machine_patches = {
    for name, node in var.nodes : name => yamlencode({
      machine = merge(
        {
          network = {
            hostname    = name
            nameservers = [var.dns_server]
            interfaces = [
              merge(
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
                },
                node.role == "servers" ? { vip = { ip = local.cluster_vip } } : {}
              )
            ]
          }
        },
        node.role == "longhorn" ? {
          nodeLabels = {
            "node.longhorn.io/create-default-disk" = "true"
          }
        } : {}
      )
    })
  }
}
