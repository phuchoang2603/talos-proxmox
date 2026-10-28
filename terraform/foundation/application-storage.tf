locals {
  application_storage = {
    gateway = {
      repository      = "payment-gateway-fraud-detection"
      revision        = "18aa65506160b6cf14fce5cabbfc7ce849a631a3"
      policy_file     = "infra/storage/gateway-policy.json.tftpl"
      iam_user        = "payment-gateway-prod-storage"
      doppler_project = "payment-gateway-fraud-detection"
      doppler_config  = "prd"
      secret_prefix   = "OBJECT_GATEWAY"
    }
  }
  application_storage_secrets = merge([for name, storage in local.application_storage : {
    "${name}/access-key" = {
      application = name
      name        = "${storage.secret_prefix}_ACCESS_KEY_ID"
      value       = aws_iam_access_key.application_storage[name].id
    }
    "${name}/secret-key" = {
      application = name
      name        = "${storage.secret_prefix}_SECRET_ACCESS_KEY"
      value       = aws_iam_access_key.application_storage[name].secret
    }
  }]...)
}

data "github_repository_file" "application_storage_policy" {
  for_each   = local.application_storage
  repository = each.value.repository
  branch     = each.value.revision
  file       = each.value.policy_file
}

resource "aws_iam_user" "application_storage" {
  for_each = local.application_storage
  name     = each.value.iam_user
}

resource "aws_iam_user_policy" "application_storage" {
  for_each = local.application_storage
  name     = "scoped-object-storage"
  user     = aws_iam_user.application_storage[each.key].name
  policy = templatestring(data.github_repository_file.application_storage_policy[each.key].content, {
    bucket_arn = aws_s3_bucket.platform.arn
  })
}

resource "aws_iam_access_key" "application_storage" {
  for_each = local.application_storage
  user     = aws_iam_user.application_storage[each.key].name
}

resource "doppler_secret" "application_storage" {
  for_each   = nonsensitive(toset(keys(local.application_storage_secrets)))
  project    = local.application_storage[local.application_storage_secrets[each.key].application].doppler_project
  config     = local.application_storage[local.application_storage_secrets[each.key].application].doppler_config
  name       = local.application_storage_secrets[each.key].name
  value      = local.application_storage_secrets[each.key].value
  depends_on = [aws_iam_user_policy.application_storage]
}
