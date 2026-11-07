# ESO needs these tokens before it can reconcile the ClusterSecretStores, so Terraform owns them.
# The platform store uses `doppler`; each application consumer gets its own read-only
# token surfaced by foundation as ESO_<CONSUMER>_DOPPLER_TOKEN.
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
