locals {
  object_consumers = {
    training  = ["datasets", "runs"]
    artifacts = ["artifacts"]
    lakehouse = ["lakehouse"]
    backups   = ["backups"]
  }
  object_secret_values = merge({ OBJECT_STORAGE_BUCKET = aws_s3_bucket.platform.id }, [
    for consumer in keys(local.object_consumers) : {
      "OBJECT_${upper(consumer)}_ACCESS_KEY_ID"     = aws_iam_access_key.objects[consumer].id
      "OBJECT_${upper(consumer)}_SECRET_ACCESS_KEY" = aws_iam_access_key.objects[consumer].secret
    }
  ]...)
}
resource "aws_iam_user" "objects" {
  for_each = local.object_consumers
  name     = "platform-prod-${each.key}"
}
data "aws_iam_policy_document" "objects" {
  for_each = local.object_consumers
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:PutObjectTagging"]
    resources = [for prefix in each.value : "${aws_s3_bucket.platform.arn}/${prefix}/*"]
  }
  statement {
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.platform.arn]
  }
  statement {
    actions   = ["s3:ListBucket", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.platform.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = flatten([for prefix in each.value : [prefix, "${prefix}/*"]])
    }
  }
}
resource "aws_iam_user_policy" "objects" {
  for_each = local.object_consumers
  name     = "scoped-object-storage"
  user     = aws_iam_user.objects[each.key].name
  policy   = data.aws_iam_policy_document.objects[each.key].json
}
resource "aws_iam_access_key" "objects" {
  for_each = local.object_consumers
  user     = aws_iam_user.objects[each.key].name
}
resource "doppler_secret" "objects" {
  for_each = nonsensitive(toset(keys(local.object_secret_values)))
  project  = doppler_project.this.name
  config   = doppler_environment.this["prod"].slug
  name     = each.key
  value    = local.object_secret_values[each.key]
}
