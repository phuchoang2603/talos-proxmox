terraform {
  required_providers {
    talos = { source = "siderolabs/talos" }
  }
}
variable "client_configuration" {
  type      = any
  sensitive = true
}
variable "endpoint" { type = string }
variable "node" {
  type    = string
  default = null
}
resource "talos_machine_bootstrap" "this" {
  client_configuration = var.client_configuration
  node                 = coalesce(var.node, var.endpoint)
  endpoint             = var.endpoint
}
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = var.client_configuration
  node                 = coalesce(var.node, var.endpoint)
  endpoint             = var.endpoint
  depends_on           = [talos_machine_bootstrap.this]
}
output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}
