module "talos" {
  source             = "../talos"
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${google_compute_address.controlplane.address}:6443"
  controlplane_ips   = [google_compute_address.controlplane.address]
  controlplane_nodes = ["10.81.0.10"]

}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${google_compute_address.controlplane.address}:6443"
  machine_type       = "controlplane"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = concat(module.talos.common_patches, module.talos.controlplane_patches, local.cloud_patches, [
    yamlencode({ machine = { certSANs = [google_compute_address.controlplane.address] } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeAPIServerConfig", certExtraSANs = [google_compute_address.controlplane.address] }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeNodeConfig", labels = { "talos.dev/capacity-type" = "on-demand", "talos.dev/nodepool" = "controlplane" } }),
  ])
}

resource "google_compute_instance" "controlplane" {
  name         = "${var.cluster_name}-controlplane"
  zone         = var.zone
  machine_type = var.controlplane_machine_type
  tags         = concat(local.tags, ["${var.cluster_name}-controlplane"])
  boot_disk {
    auto_delete = false
    initialize_params {
      image  = var.image_id
      size   = 40
      type   = "pd-balanced"
      labels = { platform-cluster = var.cluster_name, purpose = "control-plane" }
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.cluster.id
    network_ip = "10.81.0.10"
    access_config { nat_ip = google_compute_address.controlplane.address }
  }
  metadata = { "user-data" = data.talos_machine_configuration.controlplane.machine_configuration }
  service_account {
    email  = google_service_account.node.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  lifecycle {
    ignore_changes = [metadata, boot_disk[0].initialize_params[0].image]
  }
  depends_on = [google_compute_firewall.management, google_compute_firewall.internal, terraform_data.storage_cleanup]
}

module "bootstrap" {
  source               = "../talos/bootstrap"
  client_configuration = module.talos.client_configuration
  endpoint             = google_compute_address.controlplane.address
  node                 = google_compute_instance.controlplane.network_interface[0].network_ip
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = module.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = google_compute_instance.controlplane.network_interface[0].network_ip
  endpoint                    = google_compute_address.controlplane.address
  depends_on                  = [module.bootstrap]
}
