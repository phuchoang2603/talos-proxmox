# Karpenter is owned entirely by this root so that a destroy can remove the NodePool, wait for
# Karpenter to terminate its EC2 instances, and only then remove the controller and CRDs.

# The controller's AWS key is the second Doppler-derived Secret this root owns; ESO does not manage it.
resource "kubernetes_secret_v1" "karpenter_aws" {
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

resource "helm_release" "karpenter_crd" {
  name      = "karpenter-crd"
  namespace = "kube-system"
  chart     = "${local.components}/karpenter-crd"
  values    = local.chart_values["karpenter-crd"]
  timeout   = 300

  depends_on = [data.http.apiserver_ready]
}

# Pods cannot start until Cilium is ready and Cilium itself waits on Argo CD, so do not gate on rollout.
resource "helm_release" "karpenter" {
  name         = "karpenter"
  namespace    = "kube-system"
  chart        = "${local.components}/karpenter"
  values       = local.chart_values["karpenter"]
  skip_crds    = true
  wait         = false
  reset_values = true

  set = [
    { name = "karpenter.settings.clusterName", value = local.cluster_name },
    { name = "karpenter.settings.clusterEndpoint", value = local.kube_cluster.server },
    # Restarts the controller when the AWS key rotates; it reads the key only at startup.
    { name = "karpenter.podAnnotations.credentials-checksum", value = sha256(local.secrets.KARPENTER_AWS_ACCESS_KEY_ID) },
  ]

  depends_on = [
    kubernetes_secret_v1.karpenter_aws,
    helm_release.karpenter_crd,
    helm_release.cilium,
  ]
}

# Uninstalling this release deletes the NodePool. Helm waits for its NodeClaims to finalize, which
# terminates the instances, so the controller and CRDs must outlive it. terminationGracePeriod is 30m.
resource "helm_release" "karpenter_nodes" {
  name    = "karpenter-nodes"
  chart   = "${local.components}/karpenter-nodes"
  wait    = true
  timeout = 2700

  namespace = "kube-system"

  values = concat(
    local.chart_values["karpenter-nodes"],
    [sensitive(yamlencode({
      clusterName     = local.cluster_name
      amiId           = local.secrets.AWS_WORKER_AMI_ID
      instanceProfile = "${local.cluster_name}-burst-worker"
      userData        = local.secrets.AWS_WORKER_MACHINE_CONFIG
    }))],
  )

  depends_on = [helm_release.karpenter]
}
