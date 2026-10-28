locals {
  gpu_label_key = "burst.talos.dev/workload"
  gpu_taint_key = "burst.talos.dev/gpu-training"
}

data "talos_image_factory_extensions_versions" "gpu" {
  talos_version = var.talos_version
  filters = {
    names = [
      "nvidia-open-gpu-kernel-modules-production",
      "nvidia-container-toolkit-production",
    ]
  }
}

resource "talos_image_factory_schematic" "gpu" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.gpu.extensions_info[*].name
      }
    }
  })
}

data "talos_image_factory_urls" "gpu" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.gpu.id
  platform      = "aws"
  architecture  = "amd64"
}

data "talos_machine_configuration" "worker_gpu" {
  count = var.gpu_ami_id != "" ? 1 : 0

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = local.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false

  config_patches = concat(local.worker_config_patches, [
    yamlencode({
      machine = {
        install = {
          image = data.talos_image_factory_urls.gpu.urls.installer
        }
        kernel = {
          modules = [
            { name = "nvidia" },
            { name = "nvidia_uvm" },
            { name = "nvidia_drm" },
            { name = "nvidia_modeset" },
          ]
        }
        kubelet = {
          extraArgs = {
            "cloud-provider"       = "external"
            "node-labels"          = "${local.node_label}=aws,${local.gpu_label_key}=gpu-training"
            "register-with-taints" = "${local.gpu_taint_key}=true:NoSchedule,karpenter.sh/unregistered=true:NoExecute"
          }
        }
        network = {
          kubespan = { enabled = !var.create_controlplane }
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
  ])
}
