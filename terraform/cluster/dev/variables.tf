variable "env" {
  default     = "dev"
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = var.env == "dev"
    error_message = "This entry point manages dev only."
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

variable "vm_node_name" {
  description = "Proxmox node where disk images are downloaded"
  type        = string
  default     = null
}

variable "vm_datastore_id" {
  description = "Proxmox datastore ID where ISO/images are stored"
  type        = string
  default     = null
}

variable "vm_bridge" {
  description = "Network bridge used for VM network"
  type        = string
  default     = null
}

variable "vm_ip_gateway" {
  description = "Gateway for Kubernetes VMs"
  type        = string
  default     = null
}

variable "dns_server" {
  description = "DNS server for Kubernetes VMs"
  type        = string
  default     = null
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
