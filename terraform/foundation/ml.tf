locals {
  talos_version = "v1.13.9"
  object_bucket = "platform-prod-${data.aws_caller_identity.current.account_id}-us-east-1"
}

resource "aws_s3_bucket" "platform" {
  bucket = local.object_bucket

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "platform_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.platform.arn, "${aws_s3_bucket.platform.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "platform" {
  bucket = aws_s3_bucket.platform.id
  policy = data.aws_iam_policy_document.platform_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.platform]
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

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "platform" {
  bucket = aws_s3_bucket.platform.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "platform" {
  bucket = aws_s3_bucket.platform.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Objects under runs/ expire only after the run-end step tags them expire=true, so
  # untagged (active or pinned) objects and everything under datasets/ and images/ stay.
  rule {
    id     = "expire-finished-run-objects"
    status = "Enabled"

    filter {
      and {
        prefix = "runs/"
        tags   = { expire = "true" }
      }
    }

    expiration {
      days = 14
    }
  }

  rule {
    id     = "expire-noncurrent-run-versions"
    status = "Enabled"

    filter {
      prefix = "runs/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "clean-expired-delete-markers"
    status = "Enabled"

    filter {
      prefix = "runs/"
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.platform]
}


variable "enable_gpu_images" {
  type    = bool
  default = false
}
module "image_assets" {
  count         = var.enable_gpu_images ? 1 : 0
  source        = "../image-assets"
  talos_version = local.talos_version
  bucket_name   = "platform-images-${data.aws_caller_identity.current.account_id}-us-east-1"
}
resource "doppler_secret" "gpu_ami" {
  count   = var.enable_gpu_images ? 1 : 0
  project = doppler_project.this.name
  config  = doppler_environment.this["prod"].slug
  name    = "AWS_GPU_AMI_ID"
  value   = module.image_assets[0].ami_id
}
