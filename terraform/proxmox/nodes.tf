resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.controlplane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = concat([
    yamlencode(local.common_machine_patch),
    local.node_machine_patches[each.key],
  ], local.kubespan_machine_patches, local.controlplane_machine_patches)

  depends_on = [
    module.nodes,
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  config_patches = concat([
    yamlencode(local.common_machine_patch),
    local.node_machine_patches[each.key],
  ], local.kubespan_machine_patches)

  depends_on = [
    module.nodes,
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [
    talos_machine_configuration_apply.controlplane,
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_ip
  endpoint             = local.bootstrap_ip

  depends_on = [
    talos_machine_bootstrap.this,
  ]
}
