terraform {
  required_providers {
    google = { source = "hashicorp/google" }
    talos  = { source = "siderolabs/talos" }
  }
}
variable "project_id" { type = string }
variable "region" { type = string }
variable "talos_version" { type = string }
variable "billing_account" {
  type    = string
  default = null
}
output "ci_variables" {
  value = {
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_CI_SERVICE_ACCOUNT         = google_service_account.ci.email
  }
}
output "secrets" {
  value = merge(local.object_secret_values, {
    TALOS_IMAGE_ID = google_compute_image.talos.self_link
  })
  sensitive = true
}
