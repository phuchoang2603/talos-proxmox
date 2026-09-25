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

variable "availability_zone" {
  type = string
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

variable "cluster_endpoint" {
  type = string
}

variable "machine_secrets" {
  type      = any
  sensitive = true
}
