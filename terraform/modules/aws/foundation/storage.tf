resource "aws_s3_bucket" "objects" {
  for_each = local.object_consumers
  bucket   = "talos-proxmox-prod-${each.key}-${data.aws_caller_identity.current.account_id}-${var.region}"
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "objects" {
  for_each                = local.object_consumers
  bucket                  = aws_s3_bucket.objects[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "objects" {
  for_each = local.object_consumers
  bucket   = aws_s3_bucket.objects[each.key].id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "objects" {
  for_each = local.object_consumers
  bucket   = aws_s3_bucket.objects[each.key].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "objects" {
  for_each = local.object_consumers
  bucket   = aws_s3_bucket.objects[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.objects[each.key].arn, "${aws_s3_bucket.objects[each.key].arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }]
  })
  depends_on = [aws_s3_bucket_public_access_block.objects]
}
resource "aws_iam_user" "objects" {
  for_each = local.object_consumers
  name     = "prod-objects-${each.key}"
}
resource "aws_iam_user_policy" "objects" {
  for_each = local.object_consumers
  name     = "bucket-access"
  user     = aws_iam_user.objects[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"], Resource = aws_s3_bucket.objects[each.key].arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:PutObjectTagging"], Resource = "${aws_s3_bucket.objects[each.key].arn}/*" },
    ]
  })
}
resource "aws_iam_access_key" "objects" {
  for_each = local.object_consumers
  user     = aws_iam_user.objects[each.key].name
}
