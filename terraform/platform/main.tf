locals {
  apps       = "${path.root}/../../apps"
  components = "${local.apps}/components"

  cloud_provider = var.env == "prod" ? nonsensitive(data.doppler_secrets.this.map.CLOUD_PROVIDER) : "proxmox"
  cloud_region   = var.env == "prod" ? nonsensitive(data.doppler_secrets.this.map.CLOUD_REGION) : ""

  cloud_storage = var.env == "prod" ? {
    bucket   = nonsensitive(data.doppler_secrets.this.map.OBJECT_ARTIFACTS_BUCKET)
    endpoint = nonsensitive(data.doppler_secrets.this.map.OBJECT_STORAGE_ENDPOINT)
    host     = trimprefix(nonsensitive(data.doppler_secrets.this.map.OBJECT_STORAGE_ENDPOINT), "https://")
    region   = nonsensitive(data.doppler_secrets.this.map.OBJECT_STORAGE_REGION)
  } : {}

  secrets      = data.doppler_secrets.this.map
  kubeconfig   = yamldecode(local.secrets.KUBECONFIG)
  kube_cluster = local.kubeconfig.clusters[0].cluster
  kube_user    = local.kubeconfig.users[0].user

  chart_versions = {
    for name, dir in local.chart_directories : name => yamldecode(file("${dir}/Chart.yaml")).version
  }

  chart_directories = {
    "gateway-api"        = "${local.components}/gateway-api"
    "cluster-autoscaler" = "${local.components}/cluster-autoscaler"
    "talos-ccm"          = "${local.components}/talos-ccm"
    cilium               = "${local.components}/cilium"
    "argo-cd"            = "${local.components}/argo-cd"
    "argocd-bootstrap"   = "${local.apps}/argocd/bootstrap"
  }

  # Base values plus the environment overlay, when the chart has one.
  chart_values = {
    for name, dir in local.chart_directories : name => [
      for f in ["${dir}/values.yaml", "${dir}/environments/${var.env}/values.yaml"] : file(f) if fileexists(f)
    ]
  }
}

data "doppler_secrets" "this" {
  project = "talos-proxmox"
  config  = var.env
}
