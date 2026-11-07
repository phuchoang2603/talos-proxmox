resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com", "iam.googleapis.com", "iamcredentials.googleapis.com",
    "sts.googleapis.com", "storage.googleapis.com", "cloudresourcemanager.googleapis.com",
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "talos-proxmox"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  attribute_condition = "assertion.repository_owner_id == '91061595' && assertion.repository_id == '1351657631' && assertion.repository == 'phuchoang2603/talos-proxmox' && assertion.environment == 'prod' && (assertion.ref == 'refs/heads/main' || assertion.event_name == 'pull_request')"
  oidc { issuer_uri = "https://token.actions.githubusercontent.com" }
}

resource "google_service_account" "ci" {
  account_id   = "talos-proxmox-ci"
  display_name = "Production infrastructure provisioning"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "ci_federation" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/phuchoang2603/talos-proxmox"
}

resource "google_project_iam_member" "ci" {
  for_each = toset([
    "roles/compute.admin", "roles/iam.serviceAccountAdmin", "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountUser", "roles/resourcemanager.projectIamAdmin", "roles/iam.roleAdmin",
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.ci.email}"
}
