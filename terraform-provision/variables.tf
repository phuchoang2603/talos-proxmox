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

variable "k8s_cpu_cores" {
  description = "Number of CPU cores per Kubernetes VM"
  type        = number
}

variable "k8s_cpu_type" {
  description = "CPU type for Kubernetes VMs"
  type        = string
}

variable "k8s_memory_mb" {
  description = "Memory size in MB per Kubernetes VM"
  type        = number
}

variable "k8s_datastore_id" {
  description = "Datastore ID where Kubernetes VM disks are stored"
  type        = string
}

variable "k8s_disk_size_gb" {
  description = "Disk size in GB for Kubernetes VM disks"
  type        = number
}

variable "longhorn_cpu_cores" {
  description = "Number of CPU cores per Longhorn VM"
  type        = number
}

variable "longhorn_cpu_type" {
  description = "CPU type for Longhorn VMs"
  type        = string
}

variable "longhorn_memory_mb" {
  description = "Memory size in MB per Longhorn VM"
  type        = number
}

variable "longhorn_datastore_id" {
  description = "Datastore ID where Longhorn VM disks are stored"
  type        = string
}

variable "longhorn_disk_size_gb" {
  description = "Disk size in GB for Longhorn VM disks"
  type        = number
}

variable "talos_version" {
  description = "Talos Linux version (including v prefix)"
  type        = string
  default     = "v1.12.6"
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

locals {
  network            = jsondecode(file("${path.root}/env/${var.env}/network.json"))
  k8s_nodes_raw      = jsondecode(file("${path.root}/env/${var.env}/k8s_nodes.json"))
  longhorn_nodes_raw = jsondecode(file("${path.root}/env/${var.env}/longhorn_nodes.json"))
  cluster_vip        = local.network.vip
  cluster_name       = "${var.env}-talos"
  cluster_endpoint   = "https://${local.cluster_vip}:6443"

  nodes = merge(
    {
      for name, node in local.k8s_nodes_raw : name => {
        role         = node.role
        node         = node.node
        vm_id        = node.vm_id
        address      = node.address
        ip           = split("/", node.address)[0]
        cpu_cores    = var.k8s_cpu_cores
        cpu_type     = var.k8s_cpu_type
        memory_mb    = var.k8s_memory_mb
        datastore_id = var.k8s_datastore_id
        disk_size_gb = var.k8s_disk_size_gb
      }
    },
    {
      for name, node in local.longhorn_nodes_raw : name => {
        role         = node.role
        node         = node.node
        vm_id        = node.vm_id
        address      = node.address
        ip           = split("/", node.address)[0]
        cpu_cores    = var.longhorn_cpu_cores
        cpu_type     = var.longhorn_cpu_type
        memory_mb    = var.longhorn_memory_mb
        datastore_id = var.longhorn_datastore_id
        disk_size_gb = var.longhorn_disk_size_gb
      }
    }
  )

  controlplane_nodes = { for name, node in local.nodes : name => node if node.role == "servers" }
  worker_nodes       = { for name, node in local.nodes : name => node if node.role != "servers" }
  controlplane_names = sort(keys(local.controlplane_nodes))
  bootstrap_name     = local.controlplane_names[0]
  bootstrap_ip       = local.controlplane_nodes[local.bootstrap_name].ip
  controlplane_ips   = [for name in local.controlplane_names : local.controlplane_nodes[name].ip]
}
