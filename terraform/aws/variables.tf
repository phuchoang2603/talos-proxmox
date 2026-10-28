terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    talos = {
      source = "siderolabs/talos"
    }
  }
}

variable "env" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "ami_id" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "cluster_name" {
  type = string
}



variable "gpu_ami_id" {
  type    = string
  default = ""
}

variable "management_cidrs" {
  type    = set(string)
  default = []
}
variable "controlplane_instance_type" {
  type    = string
  default = "m6a.xlarge"
}

variable "create_controlplane" {
  type    = bool
  default = true
}

variable "external_cluster" {
  type = object({
    endpoint              = string
    machine_secrets       = any
    worker_config_patches = list(string)
  })
  default   = null
  sensitive = true
  validation {
    condition     = var.create_controlplane || var.external_cluster != null
    error_message = "An external Talos cluster is required when no AWS control plane is created."
  }
}
