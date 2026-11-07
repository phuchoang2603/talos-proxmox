resource "talos_image_factory_schematic" "default" { schematic = yamlencode({ customization = {} }) }
data "talos_image_factory_urls" "default" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.default.id
  platform      = "gcp"
  architecture  = "amd64"
}

resource "google_storage_bucket" "images" {
  depends_on                  = [google_project_service.required]
  project                     = var.project_id
  name                        = "${var.project_id}-talos-images"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
}

locals {
  image_name = "talos-${replace(var.talos_version, ".", "-")}-${substr(talos_image_factory_schematic.default.id, 0, 12)}"
  image_key  = "${local.image_name}.tar.gz"
}

resource "terraform_data" "image_upload" {
  triggers_replace = [local.image_key, google_storage_bucket.images.name]
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      IMAGE_URL  = data.talos_image_factory_urls.default.urls.disk_image
      IMAGE_DEST = "gs://${google_storage_bucket.images.name}/${local.image_key}"
    }
    command = <<-EOT
      set -euo pipefail
      if gcloud storage objects describe "$IMAGE_DEST" >/dev/null 2>&1; then
        exit 0
      fi
      image_dir=$(mktemp -d)
      trap 'rm -rf "$image_dir"' EXIT
      curl -fsSL --retry 5 --retry-all-errors -o "$image_dir/talos.tar.gz" "$IMAGE_URL"
      gcloud storage cp "$image_dir/talos.tar.gz" "$IMAGE_DEST"
    EOT
  }
}

resource "google_compute_image" "talos" {
  project = var.project_id
  name    = local.image_name
  raw_disk { source = "https://storage.googleapis.com/${google_storage_bucket.images.name}/${local.image_key}" }
  guest_os_features { type = "VIRTIO_SCSI_MULTIQUEUE" }
  depends_on = [terraform_data.image_upload]
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
  platform      = "gcp"
  architecture  = "amd64"
}

locals {
  gpu_image_name = "talos-gpu-${replace(var.talos_version, ".", "-")}-${substr(talos_image_factory_schematic.gpu.id, 0, 12)}"
  gpu_image_key  = "${local.gpu_image_name}.tar.gz"
}

resource "terraform_data" "gpu_image_upload" {
  triggers_replace = [local.gpu_image_key, google_storage_bucket.images.name]
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      IMAGE_URL  = data.talos_image_factory_urls.gpu.urls.disk_image
      IMAGE_DEST = "gs://${google_storage_bucket.images.name}/${local.gpu_image_key}"
    }
    command = <<-EOT
      set -euo pipefail
      if gcloud storage objects describe "$IMAGE_DEST" >/dev/null 2>&1; then
        exit 0
      fi
      image_dir=$(mktemp -d)
      trap 'rm -rf "$image_dir"' EXIT
      curl -fsSL --retry 5 --retry-all-errors -o "$image_dir/talos.tar.gz" "$IMAGE_URL"
      gcloud storage cp "$image_dir/talos.tar.gz" "$IMAGE_DEST"
    EOT
  }
}

resource "google_compute_image" "gpu" {
  project = var.project_id
  name    = local.gpu_image_name
  raw_disk { source = "https://storage.googleapis.com/${google_storage_bucket.images.name}/${local.gpu_image_key}" }
  guest_os_features { type = "VIRTIO_SCSI_MULTIQUEUE" }
  depends_on = [terraform_data.gpu_image_upload]
}
