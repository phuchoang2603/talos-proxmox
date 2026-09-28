# The cluster root finishes before kube-apiserver serves on a fresh cluster, and the Kubernetes
# and Helm providers do not retry, so every Kubernetes read and write waits for readiness here.
data "http" "apiserver_ready" {
  url             = "${local.kube_cluster.server}/readyz"
  ca_cert_pem     = base64decode(local.kube_cluster["certificate-authority-data"])
  client_cert_pem = base64decode(local.kube_user["client-certificate-data"])
  client_key_pem  = base64decode(local.kube_user["client-key-data"])

  retry {
    attempts     = 90
    min_delay_ms = 5000
    max_delay_ms = 10000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "kube-apiserver did not become ready."
    }
  }
}
