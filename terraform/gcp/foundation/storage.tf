locals {
  object_consumers = toset(["training", "artifacts", "backups", "substrate", "gateway"])
}

resource "google_storage_bucket" "objects" {
  for_each                    = local.object_consumers
  name                        = "${var.project_id}-prod-${each.key}"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning { enabled = true }
  lifecycle { prevent_destroy = true }
  depends_on = [google_project_service.required]
}
