resource "kubernetes_secret_v1" "doppler_token" {
  metadata {
    name      = "doppler-token"
    namespace = "kube-system"
  }

  data = {
    dopplerToken = local.secrets.ESO_DOPPLER_TOKEN
  }

  depends_on = [data.http.apiserver_ready]
}
