terraform {
  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = ">= 3.0.0"
    }
    doppler = {
      source  = "DopplerHQ/doppler"
      version = ">= 1.0.0"
    }
  }
}

data "local_file" "artifacts_policy" {
  filename = "${path.module}/../../cluster/env/${var.env}/minio-artifacts-policy.json"
}

data "local_file" "gateway_policy" {
  filename = "${path.module}/../../cluster/env/${var.env}/minio-gateway-policy.json"
}

data "local_file" "substrate_policy" {
  filename = "${path.module}/../../cluster/env/${var.env}/minio-substrate-policy.json"
}

resource "minio_iam_policy" "artifacts" {
  name   = "platform-${var.env}-artifacts"
  policy = data.local_file.artifacts_policy.content
}

resource "minio_iam_policy" "gateway" {
  name   = "platform-${var.env}-gateway"
  policy = data.local_file.gateway_policy.content
}

resource "minio_iam_policy" "substrate" {
  name   = "platform-${var.env}-substrate"
  policy = data.local_file.substrate_policy.content
}

resource "minio_iam_user" "artifacts" {
  name          = "platform-${var.env}-artifacts"
  force_destroy = true
}

resource "minio_iam_user" "gateway" {
  name          = "platform-${var.env}-gateway"
  force_destroy = true
}

resource "minio_iam_user" "substrate" {
  name          = "platform-${var.env}-substrate"
  force_destroy = true
}

resource "minio_iam_user_policy_attachment" "artifacts" {
  user_name   = minio_iam_user.artifacts.name
  policy_name = minio_iam_policy.artifacts.name
}

resource "minio_iam_user_policy_attachment" "gateway" {
  user_name   = minio_iam_user.gateway.name
  policy_name = minio_iam_policy.gateway.name
}

resource "minio_iam_user_policy_attachment" "substrate" {
  user_name   = minio_iam_user.substrate.name
  policy_name = minio_iam_policy.substrate.name
}

resource "minio_iam_service_account" "artifacts" {
  target_user = minio_iam_user.artifacts.name
  depends_on  = [minio_iam_user_policy_attachment.artifacts]
}

resource "minio_iam_service_account" "gateway" {
  target_user = minio_iam_user.gateway.name
  depends_on  = [minio_iam_user_policy_attachment.gateway]
}

resource "minio_iam_service_account" "substrate" {
  target_user = minio_iam_user.substrate.name
  depends_on  = [minio_iam_user_policy_attachment.substrate]
}

resource "doppler_secret" "object_artifacts_access_key_id" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_ARTIFACTS_ACCESS_KEY_ID"
  value   = minio_iam_service_account.artifacts.access_key
}

resource "doppler_secret" "object_artifacts_secret_access_key" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_ARTIFACTS_SECRET_ACCESS_KEY"
  value   = minio_iam_service_account.artifacts.secret_key
}

resource "doppler_secret" "object_training_access_key_id" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_TRAINING_ACCESS_KEY_ID"
  value   = minio_iam_service_account.artifacts.access_key
}

resource "doppler_secret" "object_training_secret_access_key" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_TRAINING_SECRET_ACCESS_KEY"
  value   = minio_iam_service_account.artifacts.secret_key
}

resource "doppler_secret" "object_gateway_access_key_id" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_GATEWAY_ACCESS_KEY_ID"
  value   = minio_iam_service_account.gateway.access_key
}

resource "doppler_secret" "object_gateway_secret_access_key" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_GATEWAY_SECRET_ACCESS_KEY"
  value   = minio_iam_service_account.gateway.secret_key
}

resource "doppler_secret" "object_substrate_access_key_id" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_SUBSTRATE_ACCESS_KEY_ID"
  value   = minio_iam_service_account.substrate.access_key
}

resource "doppler_secret" "object_substrate_secret_access_key" {
  project = var.doppler_project
  config  = var.doppler_config
  name    = "OBJECT_SUBSTRATE_SECRET_ACCESS_KEY"
  value   = minio_iam_service_account.substrate.secret_key
}
