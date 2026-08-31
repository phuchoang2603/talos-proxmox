variable "env" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint (e.g., https://your-proxmox-ip:8006)"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Skip TLS verification"
  default     = true
}

variable "proxmox_min_tls" {
  type        = string
  description = "Minimum TLS version"
  default     = "1.3"
}

variable "proxmox_username" {
  description = "Proxmox username"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "vm_node_name" {
  description = "Proxmox node where disk images are downloaded"
  type        = string
}

variable "vm_datastore_id" {
  description = "Proxmox datastore ID where ISO/images are stored"
  type        = string
}

variable "vm_bridge" {
  description = "Network bridge used for VM network"
  type        = string
}

variable "vm_ip_gateway" {
  description = "Gateway for Kubernetes VMs"
  type        = string
}

variable "dns_server" {
  description = "DNS server for Kubernetes VMs"
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version (including v prefix)"
  type        = string
  default     = "v1.13.9"
}

variable "talos_install_disk" {
  description = "Install disk path inside the VM (virtio0 is /dev/vda)"
  type        = string
  default     = "/dev/vda"
}

variable "talos_network_interface" {
  description = "Primary NIC name inside Talos"
  type        = string
  default     = "eth0"
}
