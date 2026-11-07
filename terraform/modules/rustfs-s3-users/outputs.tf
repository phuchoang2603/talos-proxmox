output "artifacts_access_key_id" {
  value     = minio_iam_service_account.artifacts.access_key
  sensitive = true
}

output "artifacts_secret_access_key" {
  value     = minio_iam_service_account.artifacts.secret_key
  sensitive = true
}

output "gateway_access_key_id" {
  value     = minio_iam_service_account.gateway.access_key
  sensitive = true
}

output "gateway_secret_access_key" {
  value     = minio_iam_service_account.gateway.secret_key
  sensitive = true
}

output "substrate_access_key_id" {
  value     = minio_iam_service_account.substrate.access_key
  sensitive = true
}

output "substrate_secret_access_key" {
  value     = minio_iam_service_account.substrate.secret_key
  sensitive = true
}
