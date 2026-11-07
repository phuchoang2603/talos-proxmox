locals {
  rustfs_bucket = var.rustfs_enabled ? local.secrets.OBJECT_STORAGE_BUCKET : ""

  # App consumer -> scoped MinIO policy document. Each consumer gets its own
  # user + service account; the apps read OBJECT_<CONSUMER>_{ACCESS_KEY_ID,
  # SECRET_ACCESS_KEY} from Doppler.
  rustfs_consumers = var.rustfs_enabled ? {
    substrate = "${path.module}/env/${var.env}/minio-substrate-policy.json"
    artifacts = "${path.module}/env/${var.env}/minio-artifacts-policy.json"
    gateway   = "${path.module}/env/${var.env}/minio-gateway-policy.json"
  } : {}

  rustfs_consumer_secrets = var.rustfs_enabled ? merge([
    for name, _ in local.rustfs_consumers : {
      "OBJECT_${upper(name)}_ACCESS_KEY_ID"     = { type = "string", value = minio_iam_service_account.consumer[name].access_key }
      "OBJECT_${upper(name)}_SECRET_ACCESS_KEY" = { type = "string", value = minio_iam_service_account.consumer[name].secret_key }
    }
  ]...) : {}

  rustfs_connection = var.rustfs_enabled ? {
    OBJECT_STORAGE_ENDPOINT = { type = "string", value = "https://${var.rustfs_endpoint}" }
    OBJECT_STORAGE_REGION   = { type = "string", value = "us-east-1" }
  } : {}

  # Keys the platform's own config keeps.
  rustfs_platform_secrets = var.rustfs_enabled ? merge(
    local.rustfs_connection,
    { for k, v in local.rustfs_consumer_secrets : k => v if startswith(k, "OBJECT_SUBSTRATE_") }
  ) : {}

  # payment-gateway consumes OBJECT_GATEWAY_* and OBJECT_ARTIFACTS_* plus the shared
  # connection settings directly from its own Doppler project and store.
  rustfs_gateway_secrets = var.rustfs_enabled ? merge(
    local.rustfs_connection,
    { for k, v in local.rustfs_consumer_secrets : k => v if startswith(k, "OBJECT_GATEWAY_") || startswith(k, "OBJECT_ARTIFACTS_") }
  ) : {}
}

resource "minio_s3_bucket" "platform" {
  count         = var.rustfs_enabled ? 1 : 0
  bucket        = local.rustfs_bucket
  acl           = "private"
  force_destroy = false
}

resource "minio_s3_bucket_versioning" "platform" {
  count  = var.rustfs_enabled ? 1 : 0
  bucket = minio_s3_bucket.platform[0].bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "minio_iam_policy" "consumer" {
  for_each = local.rustfs_consumers
  name     = "${var.env}-${each.key}"
  policy   = file(each.value)
}

resource "minio_iam_user" "consumer" {
  for_each      = local.rustfs_consumers
  name          = "${var.env}-${each.key}"
  force_destroy = true
}

resource "minio_iam_user_policy_attachment" "consumer" {
  for_each    = local.rustfs_consumers
  user_name   = minio_iam_user.consumer[each.key].name
  policy_name = minio_iam_policy.consumer[each.key].name
}

resource "minio_iam_service_account" "consumer" {
  for_each    = local.rustfs_consumers
  target_user = minio_iam_user.consumer[each.key].name
  depends_on  = [minio_iam_user_policy_attachment.consumer]
}
