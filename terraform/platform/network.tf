# With upgrade_install and no version, the provider plans the installed version and misses local chart bumps.
resource "helm_release" "gateway_api" {
  version         = local.chart_versions["gateway-api"]
  name            = "gateway-api"
  namespace       = "kube-system"
  chart           = "${local.components}/gateway-api"
  timeout         = 300
  upgrade_install = true

  depends_on = [data.http.apiserver_ready]
}

resource "helm_release" "cilium" {
  version         = local.chart_versions["cilium"]
  name            = "cilium"
  namespace       = "kube-system"
  chart           = "${local.components}/cilium"
  values          = local.chart_values["cilium"]
  wait            = true
  timeout         = 900
  upgrade_install = true

  depends_on = [helm_release.gateway_api]
}

resource "helm_release" "talos_ccm" {
  version         = local.chart_versions["talos-ccm"]
  name            = "talos-cloud-controller-manager"
  namespace       = "kube-system"
  chart           = "${local.components}/talos-ccm"
  values          = local.chart_values["talos-ccm"]
  timeout         = 300
  upgrade_install = true

  depends_on = [helm_release.cilium]
}
