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
  default     = "v1.13.9"
}

variable "kubernetes_version" {
  description = "Kubernetes version shipped with Talos (including v prefix)"
  type        = string
  default     = "v1.36.3"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_vpc_cidr" {
  type    = string
  default = null
}

variable "aws_availability_zones" {
  description = "Availability zones that get a Karpenter worker subnet"
  type        = list(string)
  default     = ["us-east-1a"]
}

variable "aws_ami_id" {
  type    = string
  default = null
}

variable "aws_management_cidrs" {
  type    = set(string)
  default = []
  validation {
    condition     = alltrue([for cidr in var.aws_management_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)])
    error_message = "Management access must use explicit IPv4 CIDRs of /24 or narrower."
  }
}

variable "aws_controlplane_instance_type" {
  type    = string
  default = "m6a.xlarge"
}
