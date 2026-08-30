data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = [
      "qemu-guest-agent",
      "iscsi-tools",
      "util-linux-tools",
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
}

resource "talos_machine_secrets" "this" {}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = local.controlplane_ips
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

data "talos_machine_configuration" "worker" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
}

locals {
  cert_sans = concat([local.cluster_vip], local.controlplane_ips)

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
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.controlplane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = [
    yamlencode(local.common_machine_patch),
    yamlencode({
      machine = {
        network = {
          hostname    = each.key
          nameservers = [var.dns_server]
          interfaces = [
            {
              interface = var.talos_network_interface
              dhcp      = false
              addresses = [each.value.address]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.vm_ip_gateway
                }
              ]
              vip = {
                ip = local.cluster_vip
              }
            }
          ]
        }
      }
    }),
  ]

  depends_on = [
    module.nodes,
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = [
    yamlencode(local.common_machine_patch),
    yamlencode({
      machine = {
        network = {
          hostname    = each.key
          nameservers = [var.dns_server]
          interfaces = [
            {
              interface = var.talos_network_interface
              dhcp      = false
              addresses = [each.value.address]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.vm_ip_gateway
                }
              ]
            }
          ]
        }
        nodeLabels = each.value.role == "longhorn" ? {
          "node.longhorn.io/create-default-disk" = "true"
        } : {}
      }
    }),
  ]

  depends_on = [
    module.nodes,
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [
    talos_machine_configuration_apply.controlplane,
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.cluster_vip

  depends_on = [
    talos_machine_bootstrap.this,
  ]
}
