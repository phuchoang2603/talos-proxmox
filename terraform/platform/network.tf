resource "helm_release" "gateway_api" {
  name            = "gateway-api"
  namespace       = "kube-system"
  chart           = "${local.components}/gateway-api"
  timeout         = 300
  upgrade_install = true

  depends_on = [data.http.apiserver_ready]
}

resource "helm_release" "cilium" {
  name            = "cilium"
  namespace       = "kube-system"
  chart           = "${local.components}/cilium"
  values          = local.chart_values["cilium"]
  wait            = false
  timeout         = 900
  upgrade_install = true

  depends_on = [helm_release.gateway_api]
}
