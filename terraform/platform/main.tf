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
