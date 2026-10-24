locals {
  talos_version  = "v1.13.9"
  ml_bucket      = "talos-proxmox-ml-${data.aws_caller_identity.current.account_id}"
  gpu_image_key  = "images/talos-gpu-${talos_image_factory_schematic.gpu.id}-${local.talos_version}.raw"
  gpu_ami_prefix = "talos-proxmox-gpu-${local.talos_version}"
}

resource "aws_s3_bucket" "ml" {
  bucket = local.ml_bucket

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "ml_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.ml.arn, "${aws_s3_bucket.ml.arn}/*"]

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

resource "aws_s3_bucket_policy" "ml" {
  bucket = aws_s3_bucket.ml.id
  policy = data.aws_iam_policy_document.ml_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.ml]
}

resource "aws_s3_bucket_public_access_block" "ml" {
  bucket                  = aws_s3_bucket.ml.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "ml" {
  bucket = aws_s3_bucket.ml.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml" {
  bucket = aws_s3_bucket.ml.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ml" {
  bucket = aws_s3_bucket.ml.id

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

  depends_on = [aws_s3_bucket_versioning.ml]
}

data "talos_image_factory_extensions_versions" "gpu" {
  talos_version = local.talos_version
  filters = {
    names = [
      "nvidia-open-gpu-kernel-modules-production",
      "nvidia-container-toolkit-production",
    ]
  }
}

resource "talos_image_factory_schematic" "gpu" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.gpu.extensions_info[*].name
      }
    }
  })
}

data "talos_image_factory_urls" "gpu" {
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.gpu.id
  platform      = "aws"
  architecture  = "amd64"
}

data "aws_iam_policy_document" "vmimport_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vmie.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:Externalid"
      values   = ["vmimport"]
    }
  }
}

data "aws_iam_policy_document" "vmimport" {
  statement {
    actions   = ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.ml.arn, "${aws_s3_bucket.ml.arn}/images/*"]
  }

  statement {
    actions   = ["ec2:ModifySnapshotAttribute", "ec2:CopySnapshot", "ec2:RegisterImage", "ec2:Describe*"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "vmimport" {
  name               = "talos-proxmox-vmimport"
  assume_role_policy = data.aws_iam_policy_document.vmimport_trust.json
}

resource "aws_iam_role_policy" "vmimport" {
  role   = aws_iam_role.vmimport.id
  policy = data.aws_iam_policy_document.vmimport.json
}

# Talos publishes no AMI for a custom schematic and EC2 imports only uncompressed images from S3.
resource "terraform_data" "gpu_image_upload" {
  triggers_replace = [local.gpu_image_key]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      AWS_PAGER = ""
      IMAGE_URL = data.talos_image_factory_urls.gpu.urls.disk_image
      BUCKET    = aws_s3_bucket.ml.id
      KEY       = local.gpu_image_key
    }
    command = <<-EOT
      set -euo pipefail
      if aws s3api head-object --bucket "$BUCKET" --key "$KEY" >/dev/null 2>&1; then
        exit 0
      fi
      dir=$(mktemp -d)
      trap 'rm -rf "$dir"' EXIT
      curl -fsSL --retry 10 --retry-delay 15 --retry-all-errors -o "$dir/img.xz" "$IMAGE_URL"
      xz -dc "$dir/img.xz" > "$dir/img.raw"
      aws s3 cp "$dir/img.raw" "s3://$BUCKET/$KEY"
    EOT
  }

  depends_on = [aws_s3_bucket_lifecycle_configuration.ml, aws_s3_bucket_public_access_block.ml]
}

resource "aws_ebs_snapshot_import" "gpu" {
  role_name = aws_iam_role.vmimport.name

  disk_container {
    description = "Talos ${local.talos_version} NVIDIA ${talos_image_factory_schematic.gpu.id}"
    format      = "RAW"

    user_bucket {
      s3_bucket = aws_s3_bucket.ml.id
      s3_key    = local.gpu_image_key
    }
  }

  depends_on = [terraform_data.gpu_image_upload, aws_iam_role_policy.vmimport]
}

resource "aws_ami" "gpu" {
  name                = "${local.gpu_ami_prefix}-${substr(talos_image_factory_schematic.gpu.id, 0, 12)}"
  virtualization_type = "hvm"
  architecture        = "x86_64"
  boot_mode           = "uefi"
  ena_support         = true
  imds_support        = "v2.0"
  root_device_name    = "/dev/xvda"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = aws_ebs_snapshot_import.gpu.id
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

resource "doppler_secret" "gpu_ami" {
  for_each = doppler_environment.this

  project = doppler_project.this.name
  config  = each.value.slug
  name    = "AWS_GPU_AMI_ID"
  value   = aws_ami.gpu.id
}
