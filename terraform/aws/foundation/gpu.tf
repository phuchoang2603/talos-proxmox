data "talos_image_factory_extensions_versions" "gpu" {
  count         = var.enable_gpu_images ? 1 : 0
  talos_version = var.talos_version
  filters = {
    names = [
      "nvidia-open-gpu-kernel-modules-production",
      "nvidia-container-toolkit-production",
    ]
  }
}

resource "talos_image_factory_schematic" "gpu" {
  count = var.enable_gpu_images ? 1 : 0
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.gpu[0].extensions_info[*].name
      }
    }
  })
}

data "talos_image_factory_urls" "gpu" {
  count         = var.enable_gpu_images ? 1 : 0
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.gpu[0].id
  platform      = "aws"
  architecture  = "amd64"
}
