locals {
  autoscaler_image = coalesce(var.cluster_autoscaler_image, try(nonsensitive(local.secrets.AUTOSCALER_IMAGE), ""), yamldecode(file("${local.components}/cluster-autoscaler/values.yaml")).image)
}

resource "kubernetes_secret_v1" "autoscaler" {
  count = var.env == "prod" ? 1 : 0
  metadata {
    name      = "cluster-autoscaler-cloud"
    namespace = "kube-system"
  }
  data       = jsondecode(local.secrets.AUTOSCALER_CREDENTIALS)
  depends_on = [data.http.apiserver_ready]
}

resource "helm_release" "cluster_autoscaler" {
  version         = local.chart_versions["cluster-autoscaler"]
  count           = var.env == "prod" ? 1 : 0
  name            = "cluster-autoscaler"
  namespace       = "kube-system"
  chart           = "${local.components}/cluster-autoscaler"
  wait            = true
  timeout         = 300
  upgrade_install = true
  values = [yamlencode({
    enabled             = true
    image               = local.autoscaler_image
    cloudProvider       = local.cloud_provider
    region              = local.cloud_region
    projectId           = local.secrets.CLOUD_PROJECT_ID
    zone                = local.secrets.CLOUD_ZONE
    groups              = jsondecode(nonsensitive(local.secrets.AUTOSCALER_GROUPS))
    credentialsChecksum = sha256(local.secrets.AUTOSCALER_CREDENTIALS)
  })]
  lifecycle {
    precondition {
      condition     = can(regex(":v1\\.37\\.[0-9]+@sha256:[a-f0-9]{64}$", local.autoscaler_image))
      error_message = "Set AUTOSCALER_IMAGE or cluster_autoscaler_image to a digest-pinned v1.37.x image compatible with Kubernetes v1.37.2 before deploying prod."
    }
  }
  depends_on = [kubernetes_secret_v1.autoscaler, helm_release.talos_ccm]
}
