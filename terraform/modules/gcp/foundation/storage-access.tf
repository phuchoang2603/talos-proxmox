resource "google_service_account" "objects" {
  for_each   = local.object_consumers
  account_id = "prod-objects-${each.key}"
  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "objects" {
  for_each = local.object_consumers
  bucket   = google_storage_bucket.objects[each.value].name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${google_service_account.objects[each.key].email}"
  dynamic "condition" {
    for_each = contains(keys(local.object_prefixes), each.key) ? [local.object_prefixes[each.key]] : []
    content {
      title = "${each.key}-objects"
      expression = join(" || ", concat([
        "resource.name == \"projects/_/buckets/${google_storage_bucket.objects[each.value].name}\""
        ], [for prefix in condition.value :
        "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.objects[each.value].name}/objects/${prefix}\")"
      ]))
    }
  }
}

resource "google_storage_hmac_key" "objects" {
  for_each              = local.object_consumers
  service_account_email = google_service_account.objects[each.key].email
}

locals {
  object_prefixes = {
    artifacts = ["artifacts/", "datasets/", "runs/"]
  }
  object_secret_values = merge({
    OBJECT_STORAGE_BUCKET   = google_storage_bucket.objects["platform"].name
    OBJECT_STORAGE_ENDPOINT = "https://storage.googleapis.com"
    OBJECT_STORAGE_REGION   = "auto"
    OBJECT_ARTIFACTS_BUCKET = google_storage_bucket.objects["platform"].name
    }, [for consumer in keys(local.object_consumers) : {
      "OBJECT_${upper(consumer)}_ACCESS_KEY_ID"     = google_storage_hmac_key.objects[consumer].access_id
      "OBJECT_${upper(consumer)}_SECRET_ACCESS_KEY" = google_storage_hmac_key.objects[consumer].secret
  }]...)
}
