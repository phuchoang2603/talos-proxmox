locals {
  apps       = "${path.root}/../../apps"
  components = "${local.apps}/components"

  secrets      = data.doppler_secrets.this.map
  kubeconfig   = yamldecode(local.secrets.KUBECONFIG)
  kube_cluster = local.kubeconfig.clusters[0].cluster
  kube_user    = local.kubeconfig.users[0].user

  # Base values plus the environment overlay, when the chart has one.
  chart_values = {
    for name, dir in {
      cilium             = "${local.components}/cilium"
      "argo-cd"          = "${local.components}/argo-cd"
      "argocd-bootstrap" = "${local.apps}/argocd/bootstrap"
      } : name => [
      for f in ["${dir}/values.yaml", "${dir}/environments/${var.env}/values.yaml"] : file(f) if fileexists(f)
    ]
  }
}

data "doppler_secrets" "this" {
  project = "talos-proxmox"
  config  = var.env
}
