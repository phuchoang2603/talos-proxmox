variable "env" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }

  validation {
    condition     = trimprefix(terraform.workspace, "talos-cluster-") == var.env
    error_message = "TF_WORKSPACE must be talos-cluster-<env> so one environment cannot plan against the other's state."
  }
}

variable "cloud_provider" {
  type = string
  validation {
    condition     = contains(["gcp", "aws", "proxmox"], var.cloud_provider)
    error_message = "cloud_provider must be gcp, aws, or proxmox."
  }
}

variable "talos_version" {
  description = "Talos Linux version (including v prefix)"
  type        = string
  default     = "v1.14.5"
}

variable "kubernetes_version" {
  description = "Kubernetes version shipped with Talos (including v prefix)"
  type        = string
  default     = "v1.37.2"
}

variable "management_cidrs" {
  type    = set(string)
  default = []
}

variable "worker_min" {
  type    = number
  default = 3
}

variable "worker_max" {
  type    = number
  default = 4
}

variable "enable_spot" {
  type    = bool
  default = true
}

variable "spot_max" {
  type    = number
  default = 4
}

# --- Proxmox ---------------------------------------------------------------

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

# --- GCP -------------------------------------------------------------------

variable "gcp_project_id" {
  type    = string
  default = "talos-proxmox"
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
  validation {
    condition     = startswith(var.gcp_zone, "${var.gcp_region}-")
    error_message = "The zone must belong to gcp_region."
  }
}

variable "gcp_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "gcp_controlplane_machine_type" {
  type    = string
  default = null
}

variable "gcp_controlplane_schedulable" {
  type    = bool
  default = true
}

variable "gcp_gpu_enabled" {
  type    = bool
  default = false
}

variable "gcp_gpu_zone" {
  type    = string
  default = null
}

# --- AWS -------------------------------------------------------------------

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_zone" {
  type    = string
  default = "us-east-1a"
  validation {
    condition     = startswith(var.aws_zone, var.aws_region)
    error_message = "aws_zone must belong to aws_region."
  }
}

variable "aws_machine_type" {
  type    = string
  default = "m6a.xlarge"
}

# --- RustFS / object storage ----------------------------------------------

variable "rustfs_enabled" {
  description = "Manage RustFS/MinIO buckets, policies, and service accounts for this environment."
  type        = bool
  default     = false
}

variable "rustfs_endpoint" {
  type    = string
  default = "minio.home.phuchoang.sbs"
}

# --- Doppler ---------------------------------------------------------------

variable "doppler_project" {
  type    = string
  default = "talos-proxmox"
}

variable "doppler_config" {
  type    = string
  default = null
}
