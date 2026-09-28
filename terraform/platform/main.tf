locals {
  apps       = "${path.root}/../../apps"
  components = "${local.apps}/components"
  inventory  = jsondecode(file("${path.root}/../cluster/env/${var.env}/k8s_nodes.json"))

  secrets       = data.doppler_secrets.this.map
  kubeconfig    = yamldecode(local.secrets.KUBECONFIG)
  kube_cluster  = local.kubeconfig.clusters[0].cluster
  kube_user     = local.kubeconfig.users[0].user
  talosconfig   = yamldecode(local.secrets.TALOSCONFIG)
  talos_context = local.talosconfig.contexts[local.talosconfig.context]

  controlplane_ips = sort([for node in values(local.inventory) : split("/", node.address)[0] if node.role == "servers"])
  worker_ips       = sort([for node in values(local.inventory) : split("/", node.address)[0] if node.role != "servers"])

  # Base values plus the environment overlay, when the component has one.
  component_values = {
    for name in ["cilium", "argo-cd"] : name => [
      for f in [
        "${local.components}/${name}/values.yaml",
        "${local.components}/${name}/environments/${var.env}/values.yaml",
      ] : file(f) if fileexists(f)
    ]
  }
}

data "doppler_secrets" "this" {
  project = "talos-proxmox"
  config  = var.env
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

resource "helm_release" "gateway_api" {
  name      = "gateway-api"
  namespace = "kube-system"
  chart     = "${local.components}/gateway-api"
  timeout   = 300

  depends_on = [data.http.apiserver_ready]
}

# SPIRE needs a StorageClass that Argo CD installs later, so Helm must not wait for it.
resource "helm_release" "cilium" {
  name      = "cilium"
  namespace = "kube-system"
  chart     = "${local.components}/cilium"
  values    = local.component_values["cilium"]
  wait      = false
  timeout   = 900

  depends_on = [helm_release.gateway_api]
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

resource "kubernetes_namespace_v1" "external_secrets_auth" {
  metadata {
    name = "external-secrets-auth"
  }

  depends_on = [data.http.apiserver_ready]
}

resource "kubernetes_secret_v1" "doppler_token" {
  metadata {
    name      = "doppler-token"
    namespace = kubernetes_namespace_v1.external_secrets_auth.metadata[0].name
  }

  data = {
    dopplerToken = local.secrets.ESO_DOPPLER_TOKEN
  }
}

resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  namespace        = "argo-cd"
  create_namespace = true
  chart            = "${local.components}/argo-cd"
  values           = local.component_values["argo-cd"]
  timeout          = 900

  depends_on = [data.talos_cluster_health.fixed, data.kubernetes_nodes.fixed]
}

resource "helm_release" "argocd_bootstrap" {
  name      = "argocd-bootstrap"
  namespace = helm_release.argo_cd.namespace
  chart     = "${local.apps}/argocd/bootstrap"
  wait      = false

  set = [
    { name = "cluster", value = var.env },
    { name = "repoURL", value = var.repo_url },
    { name = "targetRevision", value = var.target_revision },
  ]
}
