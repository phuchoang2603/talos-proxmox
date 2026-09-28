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
