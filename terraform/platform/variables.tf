variable "env" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }

  validation {
    condition     = trimprefix(terraform.workspace, "talos-platform-") == var.env
    error_message = "TF_WORKSPACE must be talos-platform-<env> so one environment cannot plan against the other's state."
  }
}

variable "repo_url" {
  description = "Git repository Argo CD reconciles the platform from"
  type        = string
  default     = "https://github.com/phuchoang2603/talos-proxmox.git"
}

variable "target_revision" {
  description = "Git revision Argo CD reconciles the platform from"
  type        = string
  default     = "main"
}
