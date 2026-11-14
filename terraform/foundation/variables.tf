variable "gcp_project_id" {
  type    = string
  default = "talos-proxmox"
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_billing_account" {
  description = "Optional billing account ID for a monthly budget alert; alerts do not cap spending."
  type        = string
  default     = null
}

variable "talos_version" {
  type    = string
  default = "v1.14.5"
}

variable "cloud_provider" {
  type    = string
  default = "gcp"
  validation {
    condition     = contains(["gcp", "aws", "proxmox"], var.cloud_provider)
    error_message = "cloud_provider must be gcp, aws, or proxmox."
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "aws_talos_ami_id" {
  type    = string
  default = ""
}
variable "enable_aws_gpu_images" {
  type    = bool
  default = false
}

variable "dev_management_cidrs" {
  description = "Operator/CI CIDRs allowed to reach the dev (Proxmox) cluster; informational, mirrors the prod cloud contract."
  type        = list(string)
  default     = []
}

variable "rustfs_endpoint" {
  type    = string
  default = "minio.home.phuchoang.sbs"
}
