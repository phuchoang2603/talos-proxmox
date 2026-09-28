locals {
  controlplane_ips = sort([for node in values(local.inventory) : split("/", node.address)[0] if node.role == "servers"])
  worker_ips       = sort([for node in values(local.inventory) : split("/", node.address)[0] if node.role != "servers"])
}

# The cluster root finishes before kube-apiserver serves on a fresh cluster, and the Kubernetes
# and Helm providers do not retry, so every Kubernetes read and write waits for readiness here.
data "http" "apiserver_ready" {
  url             = "${local.kube_cluster.server}/readyz"
  ca_cert_pem     = base64decode(local.kube_cluster["certificate-authority-data"])
  client_cert_pem = base64decode(local.kube_user["client-certificate-data"])
  client_key_pem  = base64decode(local.kube_user["client-key-data"])

  retry {
    attempts     = 90
    min_delay_ms = 5000
    max_delay_ms = 10000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "kube-apiserver did not become ready."
    }
  }
}

data "kubernetes_nodes" "burst" {
  metadata {
    labels = { "burst.talos.dev/compute" = "aws" }
  }

  depends_on = [data.http.apiserver_ready]
}

# talos_cluster_health fails on any Kubernetes node missing from its node lists, so it can only
# gate the cluster while no burst worker is registered; otherwise only fixed-node readiness is checked.
data "talos_cluster_health" "fixed" {
  count = length(data.kubernetes_nodes.burst.nodes) == 0 ? 1 : 0

  client_configuration = {
    ca_certificate     = local.talos_context.ca
    client_certificate = local.talos_context.crt
    client_key         = local.talos_context.key
  }
  endpoints           = local.talos_context.endpoints
  control_plane_nodes = local.controlplane_ips
  worker_nodes        = local.worker_ips
  timeouts = {
    read = "15m"
  }

  depends_on = [helm_release.cilium]
}

data "kubernetes_nodes" "fixed" {
  count = length(data.kubernetes_nodes.burst.nodes) == 0 ? 0 : 1

  depends_on = [helm_release.cilium]

  lifecycle {
    postcondition {
      condition = length(setsubtract(keys(local.inventory), [
        for node in self.nodes : node.metadata[0].name
        if anytrue([for c in node.status[0].conditions : c.type == "Ready" && c.status == "True"])
      ])) == 0
      error_message = "Every node in k8s_nodes.json must be registered and Ready."
    }
  }
}
