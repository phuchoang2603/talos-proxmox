locals {
  gateway_project = local.consumer_projects.gateway.project

  # Dev object creds come from the RustFS service accounts provisioned in rustfs.tf.
  rustfs_access_keys = {
    for name, _ in local.rustfs_consumers : name => {
      access_key_id     = minio_iam_service_account.consumer[name].access_key
      secret_access_key = minio_iam_service_account.consumer[name].secret_key
    }
  }

  rustfs_connection = {
    OBJECT_STORAGE_ENDPOINT = "https://${var.rustfs_endpoint}"
    OBJECT_STORAGE_REGION   = "us-east-1"
  }

  # Platform keeps substrate; the payment-gateway project owns gateway + artifacts.
  rustfs_platform_secrets = local.rustfs_enabled ? merge(local.rustfs_connection, {
    OBJECT_SUBSTRATE_ACCESS_KEY_ID     = local.rustfs_access_keys.substrate.access_key_id
    OBJECT_SUBSTRATE_SECRET_ACCESS_KEY = local.rustfs_access_keys.substrate.secret_access_key
  }) : {}

  rustfs_gateway_secrets = local.rustfs_enabled ? merge(local.rustfs_connection, {
    OBJECT_GATEWAY_ACCESS_KEY_ID       = local.rustfs_access_keys.gateway.access_key_id
    OBJECT_GATEWAY_SECRET_ACCESS_KEY   = local.rustfs_access_keys.gateway.secret_access_key
    OBJECT_ARTIFACTS_ACCESS_KEY_ID     = local.rustfs_access_keys.artifacts.access_key_id
    OBJECT_ARTIFACTS_SECRET_ACCESS_KEY = local.rustfs_access_keys.artifacts.secret_access_key
    CLICKHOUSE_GRAFANA_PASSWORD        = data.doppler_secrets.platform_dev[0].map.CLICKHOUSE_GRAFANA_PASSWORD
  }) : {}

  # Prod object creds come from the cloud foundation module (GCS HMAC keys or AWS
  # IAM access keys) via local.cloud_secrets; mirror the gateway-owned subset into
  # the consumer project.
  gateway_prod_secrets = var.cloud_provider == "proxmox" ? {} : {
    OBJECT_GATEWAY_ACCESS_KEY_ID       = local.cloud_secrets.OBJECT_GATEWAY_ACCESS_KEY_ID
    OBJECT_GATEWAY_SECRET_ACCESS_KEY   = local.cloud_secrets.OBJECT_GATEWAY_SECRET_ACCESS_KEY
    OBJECT_ARTIFACTS_ACCESS_KEY_ID     = local.cloud_secrets.OBJECT_ARTIFACTS_ACCESS_KEY_ID
    OBJECT_ARTIFACTS_SECRET_ACCESS_KEY = local.cloud_secrets.OBJECT_ARTIFACTS_SECRET_ACCESS_KEY
    OBJECT_STORAGE_ENDPOINT            = local.cloud_secrets.OBJECT_STORAGE_ENDPOINT
    OBJECT_STORAGE_REGION              = local.cloud_secrets.OBJECT_STORAGE_REGION
    CLICKHOUSE_GRAFANA_PASSWORD        = data.doppler_secrets.platform_prod[0].map.CLICKHOUSE_GRAFANA_PASSWORD
  }
}

resource "doppler_secret" "object_platform_dev" {
  for_each = nonsensitive(toset(keys(local.rustfs_platform_secrets)))
  project  = doppler_project.this.name
  config   = doppler_environment.this["dev"].slug
  name     = each.key
  value    = local.rustfs_platform_secrets[each.key]
}

resource "doppler_secret" "object_gateway_dev" {
  for_each = nonsensitive(toset(keys(local.rustfs_gateway_secrets)))
  project  = local.gateway_project
  config   = local.consumer_projects.gateway.config["dev"]
  name     = each.key
  value    = local.rustfs_gateway_secrets[each.key]
}

resource "doppler_secret" "object_gateway_prod" {
  for_each = nonsensitive(toset(keys(local.gateway_prod_secrets)))
  project  = local.gateway_project
  config   = local.consumer_projects.gateway.config["prod"]
  name     = each.key
  value    = local.gateway_prod_secrets[each.key]
}
