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

resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.vm_datastore_id
  node_name               = var.vm_node_name
  file_name               = "${var.env}-talos-${var.talos_version}-nocloud-amd64.img"
  overwrite               = false
  decompression_algorithm = "zst"
  url                     = data.talos_image_factory_urls.this.urls.disk_image
}
