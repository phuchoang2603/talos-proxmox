locals {
  cluster_name       = "${var.env}-talos"
  cluster_endpoint   = "https://${local.bootstrap_ip}:6443"
  controlplane_nodes = { for name, node in var.nodes : name => node if node.role == "servers" }
  controlplane_names = sort(keys(local.controlplane_nodes))
  bootstrap_name     = local.controlplane_names[0]
  bootstrap_ip       = split("/", local.controlplane_nodes[local.bootstrap_name].address)[0]
  controlplane_ips   = [for name in local.controlplane_names : split("/", local.controlplane_nodes[name].address)[0]]
  cert_sans          = local.controlplane_ips
  gpu_nodes          = { for name, node in var.nodes : name => node if length(node.gpu_pci) > 0 }

  common_machine_patches = [
    yamlencode({ machine = { certSANs = local.cert_sans } }),
  ]

  local_storage_kubelet_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", "$patch" = "delete" }),
    yamlencode({
      machine = {
        kubelet = {
          image = "ghcr.io/siderolabs/kubelet:${var.kubernetes_version}"
          extraConfig = {
            systemReserved = { cpu = "250m", memory = "1Gi" }
            kubeReserved   = { cpu = "250m", memory = "512Mi" }
          }
          extraMounts = [{
            destination = "/var/mnt/local-path-provisioner"
            type        = "bind"
            source      = "/var/mnt/local-path-provisioner"
            options     = ["bind", "rshared", "rw"]
          }]
        }
      }
    }),
  ]

  kubespan_machine_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeSpanConfig", enabled = true }),
  ]

  controlplane_machine_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeAPIServerConfig", certExtraSANs = local.cert_sans }),
    yamlencode({
      apiVersion                  = "v1alpha1"
      kind                        = "KubeTalosAPIAccessConfig"
      allowedRoles                = ["os:reader"]
      allowedKubernetesNamespaces = ["kube-system"]
    }),
  ]

  node_machine_patches = {
    for name, node in var.nodes : name => concat([
      yamlencode({
        apiVersion   = "v1alpha1"
        kind         = "UnattendedInstallConfig"
        provisioning = { diskSelector = { match = "disk.dev_path == \"${var.talos_install_disk}\"" } }
        installer    = { image = contains(keys(local.gpu_nodes), name) ? one(data.talos_image_factory_urls.gpu[*].urls.installer) : data.talos_image_factory_urls.default.urls.installer }
      }),
      yamlencode({ apiVersion = "v1alpha1", kind = "ResolverConfig", nameservers = [{ address = var.dns_server }] }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "LinkConfig"
        name       = var.talos_network_interface
        up         = true
        addresses  = [{ address = node.address }]
        routes     = [{ gateway = var.vm_ip_gateway }]
      }),
      ],
      contains(keys(local.gpu_nodes), name) ? local.gpu_machine_patches : [],
      node.nvme_pci != null ? local.nvme_volume_patches[node.role] : [],
    )
  }

  gpu_machine_patches = concat(
    [yamlencode({ apiVersion = "v1alpha1", kind = "KubeNodeConfig", labels = { "nvidia.com/gpu.deploy.device-plugin" = "false" } })],
    [for module in ["nvidia", "nvidia_uvm", "nvidia_drm", "nvidia_modeset"] : yamlencode({ apiVersion = "v1alpha1", kind = "KernelModuleConfig", name = module })],
  )

  nvme_disk_selector = { match = "disk.transport == \"nvme\" && !system_disk" }

  nvme_local_path_volume = yamlencode({
    apiVersion   = "v1alpha1"
    kind         = "UserVolumeConfig"
    name         = "local-path-provisioner"
    provisioning = { diskSelector = local.nvme_disk_selector, minSize = "50GiB", grow = true }
  })

  nvme_volume_patches = {
    servers = [
      yamlencode({
        apiVersion   = "v1alpha1"
        kind         = "VolumeConfig"
        name         = "ETCD"
        provisioning = { diskSelector = local.nvme_disk_selector, minSize = "10GiB", maxSize = "10GiB" }
      }),
      local.nvme_local_path_volume,
    ]
    worker = [local.nvme_local_path_volume]
  }
}
