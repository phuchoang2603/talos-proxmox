variable "env" {
  default     = "prod"
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = var.env == "prod"
    error_message = "This entry point manages prod only."
  }

  validation {
    condition     = trimprefix(terraform.workspace, "talos-cluster-") == var.env
    error_message = "TF_WORKSPACE must be talos-cluster-<env> so one environment cannot plan against the other's state."
  }
}

variable "talos_version" {
  description = "Talos Linux version (including v prefix)"
  type        = string
  default     = "v1.14.5"
}

variable "kubernetes_version" {
  description = "Kubernetes version shipped with Talos (including v prefix)"
  type        = string
  default     = "v1.37.2"
}

variable "gcp_project_id" {
  type    = string
  default = "talos-proxmox"
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
  validation {
    condition     = startswith(var.gcp_zone, "${var.gcp_region}-")
    error_message = "The zone must belong to gcp_region."
  }
}

variable "management_cidrs" {
  type    = set(string)
  default = []
}

variable "gcp_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "gcp_gpu_enabled" {
  type    = bool
  default = false
}
variable "gcp_gpu_zone" {
  type    = string
  default = null
}

variable "worker_min" {
  type    = number
  default = 3
}

variable "worker_max" {
  type    = number
  default = 4
}

variable "enable_spot" {
  type    = bool
  default = true
}

variable "spot_max" {
  type    = number
  default = 4
}

variable "cloud_provider" {
  type    = string
  default = "gcp"
  validation {
    condition     = contains(["gcp", "aws"], var.cloud_provider)
    error_message = "cloud_provider must be gcp or aws."
  }
  validation {
    condition     = var.cloud_provider == nonsensitive(local.secrets.CLOUD_PROVIDER)
    error_message = "cloud_provider must match the foundation CLOUD_PROVIDER setting."
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "aws_zone" {
  type    = string
  default = "us-east-1a"
  validation {
    condition     = startswith(var.aws_zone, var.aws_region)
    error_message = "aws_zone must belong to aws_region."
  }
}
variable "aws_machine_type" {
  type    = string
  default = "m6a.xlarge"
}
