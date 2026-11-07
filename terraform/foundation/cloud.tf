module "gcp" {
  count           = var.cloud_provider == "gcp" ? 1 : 0
  source          = "../modules/gcp/foundation"
  project_id      = var.gcp_project_id
  region          = var.gcp_region
  billing_account = var.gcp_billing_account
  talos_version   = var.talos_version
}
module "aws" {
  count             = var.cloud_provider == "aws" ? 1 : 0
  source            = "../modules/aws/foundation"
  region            = var.aws_region
  talos_version     = var.talos_version
  ami_id            = var.aws_talos_ami_id
  enable_gpu_images = var.enable_aws_gpu_images
}
locals {
  cloud_secrets      = var.cloud_provider == "gcp" ? module.gcp[0].secrets : module.aws[0].secrets
  cloud_ci_variables = var.cloud_provider == "gcp" ? module.gcp[0].ci_variables : module.aws[0].ci_variables
}
resource "github_actions_environment_variable" "cloud" {
  for_each      = merge(local.cloud_ci_variables, { CLOUD_PROVIDER = var.cloud_provider })
  repository    = local.github_repository
  environment   = github_repository_environment.this["prod"].environment
  variable_name = each.key
  value         = each.value
}
resource "doppler_secret" "cloud" {
  for_each = nonsensitive(toset(keys(local.cloud_secrets)))
  project  = doppler_project.this.name
  config   = doppler_environment.this["prod"].slug
  name     = each.key
  value    = local.cloud_secrets[each.key]
}
resource "doppler_secret" "cloud_provider" {
  project = doppler_project.this.name
  config  = doppler_environment.this["prod"].slug
  name    = "CLOUD_PROVIDER"
  value   = var.cloud_provider
}
resource "doppler_secret" "dev_object_bucket" {
  project = doppler_project.this.name
  config  = doppler_environment.this["dev"].slug
  name    = "OBJECT_STORAGE_BUCKET"
  value   = "platform-dev"
}

# Dev runs on Proxmox, which has no cloud foundation module; write the same
# cloud contract keys prod gets so the unified cluster root reads both configs
# identically.
resource "doppler_secret" "dev_cloud_provider" {
  project = doppler_project.this.name
  config  = doppler_environment.this["dev"].slug
  name    = "CLOUD_PROVIDER"
  value   = "proxmox"
}

resource "doppler_secret" "dev_management_cidrs" {
  project = doppler_project.this.name
  config  = doppler_environment.this["dev"].slug
  name    = "CLOUD_MANAGEMENT_CIDRS"
  value   = jsonencode(var.dev_management_cidrs)
}
