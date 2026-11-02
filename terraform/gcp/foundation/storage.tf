locals {
  object_consumers = {
    training  = "platform"
    gateway   = "platform"
    artifacts = "artifacts"
    substrate = "substrate"
  }
  object_buckets = toset(values(local.object_consumers))
}

resource "google_storage_bucket" "objects" {
  for_each                    = local.object_buckets
  name                        = "${var.project_id}-prod-${each.key}"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  versioning { enabled = true }
  lifecycle { prevent_destroy = true }
  depends_on = [google_project_service.required]
}
