locals {
  doppler_project  = "talos-proxmox"
  hcp_organization = "phuchoang2603"
  environments = {
    dev  = "Development"
    prod = "Production"
  }

  consumer_projects = {
    marketplace = {
      project = "refurbished-marketplace"
      config  = { dev = "dev", prod = "prd" }
    }
    gateway = {
      project = "payment-gateway-fraud-detection"
      config  = { dev = "dev", prod = "prd" }
    }
  }

  consumer_tokens = merge([
    for key, consumer in local.consumer_projects : {
      for env in keys(local.environments) : "${key}-${env}" => {
        key          = key
        platform_env = env
        project      = consumer.project
        config       = consumer.config[env]
      }
    }
  ]...)
}
