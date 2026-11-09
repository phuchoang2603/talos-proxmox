data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = local.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = each.value.role == "servers" ? "controlplane" : "worker"
  machine_secrets    = module.talos.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  docs               = false
  examples           = false
  config_patches = concat(
    module.talos.common_patches,
    each.value.role == "servers" ? module.talos.controlplane_patches : [],
    local.common_machine_patches,
    local.local_storage_kubelet_patches,
    local.node_machine_patches[each.key],
    [yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", hostname = each.key, auto = "off" })],
    local.kubespan_machine_patches,
    each.value.role == "servers" ? local.controlplane_machine_patches : [],
  )
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = module.talos.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = split("/", each.value.address)[0]
  endpoint                    = split("/", each.value.address)[0]

  depends_on = [module.nodes]
}

module "bootstrap" {
  source               = "../talos/bootstrap"
  client_configuration = module.talos.client_configuration
  endpoint             = local.bootstrap_ip
  depends_on           = [talos_machine_configuration_apply.node]
}
