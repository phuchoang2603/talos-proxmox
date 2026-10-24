locals {
  doppler_project = "talos-proxmox"
  secrets         = data.doppler_secrets.this.map

  gpu_enabled      = try(local.secrets.AWS_GPU_AMI_ID, "") != ""
  gpu_secret_types = local.gpu_enabled ? { AWS_GPU_WORKER_MACHINE_CONFIG = "string" } : {}

  gpu_secret_values = local.gpu_enabled ? {
    AWS_GPU_WORKER_MACHINE_CONFIG = module.aws.gpu_worker_machine_configuration
  } : {}

  generated_secret_types = merge(local.gpu_secret_types, {
    KUBECONFIG                      = "yaml"
    TALOSCONFIG                     = "yaml"
    KARPENTER_AWS_ACCESS_KEY_ID     = "string"
    KARPENTER_AWS_SECRET_ACCESS_KEY = "string"
    AWS_WORKER_MACHINE_CONFIG       = "string"
    AWS_WORKER_AMI_ID               = "string"
  })

  generated_secret_values = merge(local.gpu_secret_values, {
    KUBECONFIG                      = module.proxmox.kubeconfig
    TALOSCONFIG                     = module.proxmox.talosconfig
    KARPENTER_AWS_ACCESS_KEY_ID     = module.aws.karpenter_access_key_id
    KARPENTER_AWS_SECRET_ACCESS_KEY = module.aws.karpenter_secret_access_key
    AWS_WORKER_MACHINE_CONFIG       = module.aws.worker_machine_configuration
    AWS_WORKER_AMI_ID               = module.aws.worker_ami_id
  })
}

data "doppler_secrets" "this" {
  project = local.doppler_project
  config  = var.env
}

resource "doppler_secret" "generated" {
  for_each = local.generated_secret_types

  project    = local.doppler_project
  config     = var.env
  name       = each.key
  value      = local.generated_secret_values[each.key]
  value_type = each.value
}
