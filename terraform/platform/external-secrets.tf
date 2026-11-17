locals {
  doppler_tokens = {
    "doppler-token"             = local.secrets.ESO_DOPPLER_TOKEN
    "marketplace-doppler-token" = local.secrets.ESO_MARKETPLACE_DOPPLER_TOKEN
    "gateway-doppler-token"     = local.secrets.ESO_GATEWAY_DOPPLER_TOKEN
  }
}

resource "kubernetes_secret_v1" "doppler_token" {
  for_each = local.doppler_tokens

  metadata {
    name      = each.key
    namespace = "kube-system"
  }

  data = {
    dopplerToken = each.value
  }

  depends_on = [data.http.apiserver_ready]
}
