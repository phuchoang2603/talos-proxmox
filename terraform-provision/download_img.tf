resource "proxmox_virtual_environment_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.vm_datastore_id
  node_name               = var.vm_node_name
  file_name               = "${var.env}-talos-${var.talos_version}-nocloud-amd64.img"
  overwrite               = false
  decompression_algorithm = "zst"
  url                     = data.talos_image_factory_urls.this.urls.disk_image
}
