data "talos_image_factory_extensions_versions" "default" {
  talos_version = var.talos_version
  filters = {
    names = [
      "qemu-guest-agent",
      "iscsi-tools",
      "util-linux-tools",
    ]
  }
}

data "talos_image_factory_extensions_versions" "gpu" {
  count = length(local.gpu_nodes) > 0 ? 1 : 0

  talos_version = var.talos_version
  filters = {
    names = [
      "qemu-guest-agent",
      "iscsi-tools",
      "util-linux-tools",
      "nvidia-open-gpu-kernel-modules-production",
      "nvidia-container-toolkit-production",
    ]
  }
}

resource "talos_image_factory_schematic" "default" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.default.extensions_info[*].name
      }
    }
  })
}

resource "talos_image_factory_schematic" "gpu" {
  count = length(local.gpu_nodes) > 0 ? 1 : 0

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.gpu[0].extensions_info[*].name
      }
    }
  })
}

data "talos_image_factory_urls" "default" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.default.id
  platform      = "nocloud"
  architecture  = "amd64"
}

data "talos_image_factory_urls" "gpu" {
  count = length(local.gpu_nodes) > 0 ? 1 : 0

  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.gpu[0].id
  platform      = "nocloud"
  architecture  = "amd64"
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.vm_datastore_id
  node_name               = var.vm_node_name
  file_name               = "${var.env}-talos-${var.talos_version}-nocloud-amd64.img"
  overwrite               = false
  decompression_algorithm = "zst"
  url                     = data.talos_image_factory_urls.default.urls.disk_image
}

resource "proxmox_virtual_environment_download_file" "talos_gpu_image" {
  count = length(local.gpu_nodes) > 0 ? 1 : 0

  content_type            = "iso"
  datastore_id            = var.vm_datastore_id
  node_name               = var.vm_node_name
  file_name               = "${var.env}-talos-${var.talos_version}-gpu-nocloud-amd64.img"
  overwrite               = false
  decompression_algorithm = "zst"
  url                     = data.talos_image_factory_urls.gpu[0].urls.disk_image
}
