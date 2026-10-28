moved {
  from = kubernetes_secret_v1.karpenter_aws[0]
  to   = kubernetes_secret_v1.karpenter_aws
}
moved {
  from = helm_release.karpenter[0]
  to   = helm_release.karpenter
}
moved {
  from = helm_release.karpenter_nodes[0]
  to   = helm_release.karpenter_nodes
}
