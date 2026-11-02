resource "helm_release" "argo_cd" {
  version          = local.chart_versions["argo-cd"]
  name             = "argo-cd"
  namespace        = "argo-cd"
  create_namespace = true
  chart            = "${local.components}/argo-cd"
  values           = local.chart_values["argo-cd"]
  timeout          = 900
  upgrade_install  = true

  depends_on = [helm_release.talos_ccm]
}

resource "helm_release" "argocd_bootstrap" {
  version         = local.chart_versions["argocd-bootstrap"]
  name            = "argocd-bootstrap"
  namespace       = helm_release.argo_cd.namespace
  chart           = "${local.apps}/argocd/bootstrap"
  values          = concat(local.chart_values["argocd-bootstrap"], [yamlencode({ cloudStorage = local.cloud_storage })])
  wait            = false
  upgrade_install = true

  set = [
    { name = "cluster", value = var.env },
    { name = "cloudProvider", value = local.cloud_provider },
    { name = "cloudRegion", value = local.cloud_region },
    { name = "repoURL", value = var.repo_url },
    { name = "targetRevision", value = var.target_revision },
  ]
}
