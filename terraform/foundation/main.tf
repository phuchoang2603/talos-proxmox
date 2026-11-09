locals {
  doppler_project  = "talos-proxmox"
  hcp_organization = "phuchoang2603"
  environments = {
    dev  = "Development"
    prod = "Production"
  }

  # Application-consumer Doppler projects. The platform issues each a read-only
  # ESO token and surfaces it in its own config as ESO_<KEY>_DOPPLER_TOKEN, so
  # the platform root can mount it as that consumer's ClusterSecretStore token.
  # config maps the platform env (dev/prod) to the consumer's own config slug.
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
