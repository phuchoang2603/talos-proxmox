terraform {
  required_providers {
    talos = { source = "siderolabs/talos" }
  }
}
variable "cluster_name" { type = string }
variable "cluster_endpoint" { type = string }
variable "controlplane_ips" { type = list(string) }
variable "talos_version" { type = string }
variable "kubernetes_version" { type = string }
