resource "vault_kv_secret_v2" "cluster_access" {
  mount = "kv/${var.env}"
  name  = "talos"

  data_json = jsonencode({
    talosconfig = data.talos_client_configuration.this.talos_config
    kubeconfig  = talos_cluster_kubeconfig.this.kubeconfig_raw
  })

  depends_on = [
    talos_cluster_kubeconfig.this,
  ]
}
