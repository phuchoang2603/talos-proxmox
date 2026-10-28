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

variable "management_cidrs" { type = set(string) }
variable "controlplane_instance_type" { type = string }
