resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.controlplane_nodes

  client_configuration        = module.talos.client_configuration
  machine_configuration_input = module.talos.controlplane_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = concat([
    yamlencode(module.talos.common_patch),
    yamlencode(local.common_machine_patch),
    local.node_machine_patches[each.key],
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
      auto       = "off"
    }),
  ], local.kubespan_machine_patches, local.controlplane_machine_patches)

  depends_on = [
    module.nodes,
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = module.talos.client_configuration
  machine_configuration_input = module.talos.worker_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = concat([
    yamlencode(module.talos.common_patch),
    yamlencode(local.common_machine_patch),
    local.node_machine_patches[each.key],
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
      auto       = "off"
    }),
  ], local.kubespan_machine_patches)

  depends_on = [
    module.nodes,
  ]
}

module "bootstrap" {
  source               = "../talos/bootstrap"
  client_configuration = module.talos.client_configuration
  endpoint             = local.bootstrap_ip
  depends_on           = [talos_machine_configuration_apply.controlplane]
}
