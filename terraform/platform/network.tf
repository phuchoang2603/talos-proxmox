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
