variable "env" {
  type = string
}

variable "doppler_project" {
  type    = string
  default = "talos-proxmox"
}

variable "doppler_config" {
  type = string
}
