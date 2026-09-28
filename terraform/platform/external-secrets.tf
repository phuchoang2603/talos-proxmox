# ESO needs this token before it can reconcile the `doppler` ClusterSecretStore, so Terraform owns it.
resource "kubernetes_namespace_v1" "external_secrets_auth" {
  metadata {
    name = "external-secrets-auth"
  }

  depends_on = [data.http.apiserver_ready]
}

resource "kubernetes_secret_v1" "doppler_token" {
  metadata {
    name      = "doppler-token"
    namespace = kubernetes_namespace_v1.external_secrets_auth.metadata[0].name
  }

  data = {
    dopplerToken = local.secrets.ESO_DOPPLER_TOKEN
  }
}
