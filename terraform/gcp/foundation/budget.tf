resource "google_billing_budget" "project" {
  count           = var.billing_account == null ? 0 : 1
  billing_account = var.billing_account
  display_name    = "talos-proxmox-monthly"
  budget_filter {
    projects               = ["projects/${data.google_project.current[0].number}"]
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }
  amount {
    specified_amount {
      currency_code = "USD"
      units         = "100"
    }
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.8 }
  threshold_rules { threshold_percent = 1 }
}

data "google_project" "current" {
  count      = var.billing_account == null ? 0 : 1
  project_id = var.project_id
}
