variable "project_id" { type = string }
variable "region" { type = string }
variable "zone" { type = string }
variable "cluster_name" { type = string }
variable "talos_version" { type = string }
variable "kubernetes_version" { type = string }
variable "image_id" { type = string }
variable "controlplane_machine_type" { type = string }
variable "worker_machine_type" { type = string }
variable "management_cidrs" {
  type = set(string)
  validation {
    condition = length(var.management_cidrs) > 0 && alltrue([
      for cidr in var.management_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Supply explicit operator/CI IPv4 CIDRs of /24 or narrower."
  }
}

variable "worker_min" {
  type = number
  validation {
    condition     = var.worker_min >= 0 && floor(var.worker_min) == var.worker_min && var.worker_min <= var.worker_max
    error_message = "Worker minimum must be an integer between zero and worker_max."
  }
}

variable "worker_max" {
  type = number
  validation {
    condition     = var.worker_max >= 1 && floor(var.worker_max) == var.worker_max
    error_message = "Worker maximum must be a positive integer."
  }
}

variable "enable_spot" { type = bool }
variable "spot_max" {
  type = number
  validation {
    condition     = var.spot_max >= 1 && floor(var.spot_max) == var.spot_max
    error_message = "Spot maximum must be a positive integer."
  }
}
