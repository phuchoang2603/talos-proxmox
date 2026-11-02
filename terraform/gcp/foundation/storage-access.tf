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
}

resource "google_storage_hmac_key" "objects" {
  for_each              = local.object_consumers
  service_account_email = google_service_account.objects[each.key].email
}

locals {
  object_secret_values = merge({
    OBJECT_STORAGE_BUCKET   = google_storage_bucket.objects["platform"].name
    OBJECT_STORAGE_ENDPOINT = "https://storage.googleapis.com"
    OBJECT_STORAGE_REGION   = "auto"
    }, [for consumer, bucket in local.object_consumers : merge({
      "OBJECT_${upper(consumer)}_ACCESS_KEY_ID"     = google_storage_hmac_key.objects[consumer].access_id
      "OBJECT_${upper(consumer)}_SECRET_ACCESS_KEY" = google_storage_hmac_key.objects[consumer].secret
      }, bucket == "platform" ? {} : {
      "OBJECT_${upper(consumer)}_BUCKET" = google_storage_bucket.objects[bucket].name
  })]...)
}
