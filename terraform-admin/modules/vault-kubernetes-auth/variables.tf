variable "env" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "kubernetes_host" {
  description = "Kubernetes API URL (VIP) for Vault Kubernetes auth"
  type        = string
}
