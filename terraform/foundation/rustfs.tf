data "doppler_secrets" "platform_dev" {
  project = local.doppler_project
  config  = doppler_environment.this["dev"].slug
}

data "doppler_secrets" "platform_prod" {
  count   = var.cloud_provider == "proxmox" ? 0 : 1
  project = local.doppler_project
  config  = doppler_environment.this["prod"].slug
}

locals {
  # App consumer -> scoped MinIO policy document. Each consumer gets its own user +
  # service account; apps read OBJECT_<CONSUMER>_{ACCESS_KEY_ID,SECRET_ACCESS_KEY}.
  rustfs_consumers = {
    substrate = "${path.module}/env/dev/minio-substrate-policy.json"
    artifacts = "${path.module}/env/dev/minio-artifacts-policy.json"
    gateway   = "${path.module}/env/dev/minio-gateway-policy.json"
  }
}

resource "minio_s3_bucket" "platform" {
  bucket        = "platform-dev"
  acl           = "private"
  force_destroy = false
}

resource "minio_s3_bucket_versioning" "platform" {
  bucket = minio_s3_bucket.platform.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "minio_iam_policy" "consumer" {
  for_each = local.rustfs_consumers
  name     = "dev-${each.key}"
  policy   = file(each.value)
}

resource "minio_iam_user" "consumer" {
  for_each      = local.rustfs_consumers
  name          = "dev-${each.key}"
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
  policy      = file(each.value)
  depends_on  = [minio_iam_user_policy_attachment.consumer]
}
