resource "talos_machine_secrets" "this" {}

locals {
  controlplane_patches = [
    yamlencode({
      apiVersion    = "v1alpha1"
      kind          = "KubeAuditPolicyConfig"
      configuration = yamldecode(file("${path.module}/audit-policy.yaml"))
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeAPIServerConfig"
      extraArgs  = { "runtime-config" = "certificates.k8s.io/v1beta1=true" }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeServiceAccountConfig"
      issuer     = { issuerURL = "https://kubernetes.default.svc.cluster.local" }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      taints     = { "node-role.kubernetes.io/control-plane" = { "$patch" = "delete" } }
      labels = {
        "node.kubernetes.io/exclude-from-external-load-balancers" = { "$patch" = "delete" }
      }
    }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeProxyConfig", enabled = false }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubeFlannelCNIConfig", "$patch" = "delete" }),
  ]
  common_patches = [
    yamlencode({ apiVersion = "v1alpha1", kind = "SysctlConfig", params = { "user.max_user_namespaces" = "1024" } }),
    yamlencode({ apiVersion = "v1alpha1", kind = "KubePrismConfig", port = 7445 }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeletConfig"
      config = {
        systemReserved = { cpu = "250m", memory = "1Gi" }
        kubeReserved   = { cpu = "250m", memory = "512Mi" }
      }
    }),
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.controlplane_ips
  nodes                = coalesce(var.controlplane_nodes, var.controlplane_ips)
}
