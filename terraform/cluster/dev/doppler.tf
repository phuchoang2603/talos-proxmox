locals {
  secrets = data.doppler_secrets.this.map
}
data "doppler_secrets" "this" {
  project = "talos-proxmox"
  config  = var.env
}

module "generated_secrets" {
  source = "../secret-contract"
  env    = var.env
  secrets = merge({
    KUBECONFIG                      = { type = "yaml", value = module.proxmox.kubeconfig }
    TALOSCONFIG                     = { type = "yaml", value = module.proxmox.talosconfig }
    KARPENTER_AWS_ACCESS_KEY_ID     = { type = "string", value = module.aws.karpenter_access_key_id }
    KARPENTER_AWS_SECRET_ACCESS_KEY = { type = "string", value = module.aws.karpenter_secret_access_key }
    AWS_WORKER_MACHINE_CONFIG       = { type = "string", value = module.aws.worker_machine_configuration }
    AWS_WORKER_AMI_ID               = { type = "string", value = module.aws.worker_ami_id }
    KARPENTER_INTERRUPTION_QUEUE    = { type = "string", value = module.aws.interruption_queue }
    AWS_WORKER_INSTANCE_PROFILE     = { type = "string", value = module.aws.worker_instance_profile }
  }, nonsensitive(try(local.secrets.AWS_GPU_AMI_ID, "") != "") ? { AWS_GPU_WORKER_MACHINE_CONFIG = { type = "string", value = module.aws.gpu_worker_machine_configuration } } : {})
}
