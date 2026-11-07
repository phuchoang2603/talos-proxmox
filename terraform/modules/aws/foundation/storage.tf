resource "aws_s3_bucket" "platform" {
  bucket = local.object_bucket_name
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "platform" {
  bucket                  = aws_s3_bucket.platform.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "platform" {
  bucket = aws_s3_bucket.platform.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "platform" {
  bucket = aws_s3_bucket.platform.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "platform" {
  bucket = aws_s3_bucket.platform.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.platform.arn, "${aws_s3_bucket.platform.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }]
  })
  depends_on = [aws_s3_bucket_public_access_block.platform]
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
      { Effect = "Allow", Action = ["s3:GetBucketLocation"], Resource = aws_s3_bucket.platform.arn },
      { Effect = "Allow", Action = ["s3:ListBucket", "s3:ListBucketMultipartUploads"], Resource = aws_s3_bucket.platform.arn, Condition = { StringLike = { "s3:prefix" = [for p in local.object_prefixes[each.key] : "${p}*"] } } },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts", "s3:PutObjectTagging"], Resource = [for p in local.object_prefixes[each.key] : "${aws_s3_bucket.platform.arn}/${p}*"] },
    ]
  })
}
resource "aws_iam_access_key" "objects" {
  for_each = local.object_consumers
  user     = aws_iam_user.objects[each.key].name
}
