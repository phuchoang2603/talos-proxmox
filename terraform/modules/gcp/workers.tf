data "talos_machine_configuration" "worker" {
  for_each           = local.pools
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://10.81.0.10:6443"
  machine_type       = "worker"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = concat(module.talos.common_patches, local.cloud_patches, [
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeNodeConfig", labels = {
      "talos.dev/nodepool"      = each.key
      "talos.dev/capacity-type" = each.value.spot ? "spot" : "on-demand"
    } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", config = {
      maxPods                         = 110
      shutdownGracePeriod             = "25s"
      shutdownGracePeriodCriticalPods = "5s"
    } }),
  ])
}

resource "google_compute_instance_template" "worker" {
  for_each     = local.pools
  name_prefix  = "${var.cluster_name}-${each.key}-"
  machine_type = var.worker_machine_type
  tags         = local.tags
  disk {
    source_image = var.image_id
    disk_size_gb = 40
    disk_type    = each.value.disk_type
    auto_delete  = true
    boot         = true
  }
  network_interface {
    subnetwork = google_compute_subnetwork.cluster.id
    access_config {}
  }
  service_account {
    email  = google_service_account.node.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  metadata = {
    "user-data" = data.talos_machine_configuration.worker[each.key].machine_configuration
    "kube-env" = yamlencode({
      NODE_LABELS         = "talos.dev/nodepool=${each.key},talos.dev/capacity-type=${each.value.spot ? "spot" : "on-demand"}"
      AUTOSCALER_ENV_VARS = "os=linux;arch=amd64;kube_reserved=cpu=500m,memory=1536Mi"
    })
  }
  scheduling {
    provisioning_model          = each.value.spot ? "SPOT" : "STANDARD"
    preemptible                 = each.value.spot
    automatic_restart           = !each.value.spot
    on_host_maintenance         = each.value.spot ? "TERMINATE" : "MIGRATE"
    instance_termination_action = each.value.spot ? "STOP" : null
  }
  lifecycle { create_before_destroy = true }
}

resource "google_compute_instance_group_manager" "worker" {
  for_each           = local.pools
  name               = "${var.cluster_name}-${each.key}"
  zone               = var.zone
  base_instance_name = "${var.cluster_name}-${each.key}"
  target_size        = each.value.min
  version { instance_template = google_compute_instance_template.worker[each.key].self_link_unique }
  update_policy {
    type                  = "OPPORTUNISTIC"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 0
    max_unavailable_fixed = 1
  }
  lifecycle {
    ignore_changes = [target_size]
  }
  depends_on = [module.bootstrap]
}
