# Karpenter is owned by this root; cluster teardown sweeps its AWS resources before resetting platform state.

# The controller's AWS key is the second Doppler-derived Secret this root owns; ESO does not manage it.
resource "kubernetes_secret_v1" "karpenter_aws" {
  count = var.env == "prod" ? 1 : 0
  metadata {
    name      = "karpenter-aws"
    namespace = "kube-system"
  }

  data = {
    AWS_ACCESS_KEY_ID     = local.secrets.KARPENTER_AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = local.secrets.KARPENTER_AWS_SECRET_ACCESS_KEY
  }

  depends_on = [data.http.apiserver_ready]
}

resource "helm_release" "karpenter" {
  count           = var.env == "prod" ? 1 : 0
  name            = "karpenter"
  namespace       = "kube-system"
  chart           = "${local.components}/karpenter"
  values          = local.chart_values["karpenter"]
  skip_crds       = true
  wait            = true
  timeout         = 300
  reset_values    = true
  upgrade_install = true

  set = [
    { name = "karpenter.settings.clusterName", value = local.cluster_name },
    { name = "karpenter.settings.clusterEndpoint", value = local.kube_cluster.server },
    { name = "karpenter.settings.interruptionQueue", value = local.secrets.KARPENTER_INTERRUPTION_QUEUE },
    # Restarts the controller when the AWS key rotates; it reads the key only at startup.
    { name = "karpenter.podAnnotations.credentials-checksum", value = sha256(local.secrets.KARPENTER_AWS_ACCESS_KEY_ID) },
  ]

  depends_on = [
    kubernetes_secret_v1.karpenter_aws,
    helm_release.talos_ccm,
  ]
}

# Uninstalling this release deletes the NodePool. Helm waits for its NodeClaims to finalize, which
# terminates the instances, so the controller and CRDs must outlive it. terminationGracePeriod is 30m.
resource "helm_release" "karpenter_nodes" {
  count           = var.env == "prod" ? 1 : 0
  name            = "karpenter-nodes"
  chart           = "${local.components}/karpenter-nodes"
  wait            = true
  timeout         = 2700
  upgrade_install = true

  namespace = "kube-system"

  values = concat(
    local.chart_values["karpenter-nodes"],
    [sensitive(yamlencode({
      clusterName     = local.cluster_name
      amiId           = local.secrets.AWS_WORKER_AMI_ID
      instanceProfile = local.secrets.AWS_WORKER_INSTANCE_PROFILE
      userData        = local.secrets.AWS_WORKER_MACHINE_CONFIG
    }))],
    contains(keys(local.secrets), "AWS_GPU_AMI_ID") ? [sensitive(yamlencode({
      gpu = {
        amiId    = local.secrets.AWS_GPU_AMI_ID
        userData = local.secrets.AWS_GPU_WORKER_MACHINE_CONFIG
      }
    }))] : [],
  )

  depends_on = [helm_release.karpenter]
}
