terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
    talos = {
      source = "siderolabs/talos"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }
}

variable "env" {
  type = string
}

variable "network" {
  type = object({
    vip      = string
    lb_range = string
    ingress  = string
  })
}

variable "nodes" {
  type = map(object({
    role         = string
    node         = string
    vm_id        = number
    address      = string
    ip           = string
    cpu_cores    = number
    cpu_type     = string
    memory_mb    = number
    datastore_id = string
    disk_size_gb = number
  }))
}

variable "vm_node_name" {
  type = string
}

variable "vm_datastore_id" {
  type = string
}

variable "vm_bridge" {
  type = string
}

variable "vm_ip_gateway" {
  type = string
}

variable "dns_server" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "talos_install_disk" {
  type = string
}

variable "talos_network_interface" {
  type = string
}
