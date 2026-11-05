variable "cluster_name" { type = string }
variable "cluster_endpoint" { type = string }
variable "controlplane_ips" { type = list(string) }
variable "controlplane_schedulable" {
  type    = bool
  default = true
}
variable "controlplane_nodes" {
  type    = list(string)
  default = null
}
