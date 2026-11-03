locals {
  gpu_labels = {
    "talos.dev/nodepool"                  = "gpu"
    "talos.dev/capacity-type"             = "on-demand"
    "talos.dev/cloud"                     = "gcp"
    "burst.talos.dev/workload"            = "gpu-training"
    "nvidia.com/gpu.deploy.device-plugin" = "false"
  }
}

data "talos_machine_configuration" "gpu" {
  count              = var.gpu_enabled ? 1 : 0
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://10.81.0.10:6443"
  machine_type       = "worker"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = concat(module.talos.common_patches, local.cloud_patches, [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      labels     = local.gpu_labels
      taints     = { "burst.talos.dev/gpu-training" = "true:NoSchedule" }
    }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeletConfig", config = {
      maxPods                         = 110
      shutdownGracePeriod             = "25s"
      shutdownGracePeriodCriticalPods = "5s"
    } }),
    ], [for name in ["nvidia", "nvidia_uvm", "nvidia_drm", "nvidia_modeset"] : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KernelModuleConfig"
      name       = name
  })])
}

resource "google_compute_instance_template" "gpu" {
  count        = var.gpu_enabled ? 1 : 0
  name_prefix  = "${var.cluster_name}-gpu-"
  machine_type = "g2-standard-4"
  tags         = local.tags
  disk {
    source_image = var.gpu_image_id
    disk_size_gb = 40
    disk_type    = "pd-balanced"
    auto_delete  = true
    boot         = true
    labels       = { platform-cluster = var.cluster_name, purpose = "gpu-worker" }
  }
  guest_accelerator {
    type  = "nvidia-l4"
    count = 1
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
    "user-data" = data.talos_machine_configuration.gpu[0].machine_configuration
    "kube-env" = yamlencode({
      NODE_LABELS         = join(",", [for name, value in local.gpu_labels : "${name}=${value}"])
      NODE_TAINTS         = "burst.talos.dev/gpu-training=true:NoSchedule"
      AUTOSCALER_ENV_VARS = "os=linux;arch=amd64;kube_reserved=cpu=500m,memory=1536Mi"
    })
  }
  scheduling {
    provisioning_model  = "STANDARD"
    automatic_restart   = true
    on_host_maintenance = "TERMINATE"
  }
  lifecycle { create_before_destroy = true }
}

resource "google_compute_instance_group_manager" "gpu" {
  count              = var.gpu_enabled ? 1 : 0
  name               = "${var.cluster_name}-gpu"
  zone               = coalesce(var.gpu_zone, var.zone)
  base_instance_name = "${var.cluster_name}-gpu"
  target_size        = 1
  version { instance_template = google_compute_instance_template.gpu[0].self_link_unique }
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
