locals {
  gpu_image_key  = var.enable_gpu_images ? "images/talos-gpu-${talos_image_factory_schematic.gpu[0].id}-${var.talos_version}.raw" : null
  gpu_ami_prefix = "talos-proxmox-gpu-${var.talos_version}"
}

resource "aws_s3_bucket" "images" {
  count  = var.enable_gpu_images ? 1 : 0
  bucket = local.image_bucket_name
}

resource "aws_s3_bucket_public_access_block" "images" {
  count                   = var.enable_gpu_images ? 1 : 0
  bucket                  = aws_s3_bucket.images[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  count  = var.enable_gpu_images ? 1 : 0
  bucket = aws_s3_bucket.images[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

data "aws_iam_policy_document" "vmimport_trust" {
  count = var.enable_gpu_images ? 1 : 0
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
  count = var.enable_gpu_images ? 1 : 0
  statement {
    actions   = ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.images[0].arn, "${aws_s3_bucket.images[0].arn}/images/*"]
  }

  statement {
    actions   = ["ec2:ModifySnapshotAttribute", "ec2:CopySnapshot", "ec2:RegisterImage", "ec2:Describe*"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "vmimport" {
  count              = var.enable_gpu_images ? 1 : 0
  name               = "talos-proxmox-vmimport"
  assume_role_policy = data.aws_iam_policy_document.vmimport_trust[0].json
}

resource "aws_iam_role_policy" "vmimport" {
  count  = var.enable_gpu_images ? 1 : 0
  role   = aws_iam_role.vmimport[0].id
  policy = data.aws_iam_policy_document.vmimport[0].json
}

# Talos publishes no AMI for a custom schematic and EC2 imports only uncompressed images from S3.

resource "terraform_data" "gpu_image_upload" {
  count            = var.enable_gpu_images ? 1 : 0
  triggers_replace = [local.gpu_image_key]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      AWS_PAGER = ""
      IMAGE_URL = data.talos_image_factory_urls.gpu[0].urls.disk_image
      BUCKET    = aws_s3_bucket.images[0].id
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

  depends_on = [aws_s3_bucket_public_access_block.images]
}

resource "aws_ebs_snapshot_import" "gpu" {
  count     = var.enable_gpu_images ? 1 : 0
  role_name = aws_iam_role.vmimport[0].name

  disk_container {
    description = "Talos ${var.talos_version} NVIDIA ${talos_image_factory_schematic.gpu[0].id}"
    format      = "RAW"

    user_bucket {
      s3_bucket = aws_s3_bucket.images[0].id
      s3_key    = local.gpu_image_key
    }
  }

  depends_on = [terraform_data.gpu_image_upload, aws_iam_role_policy.vmimport]
}

resource "aws_ami" "gpu" {
  count               = var.enable_gpu_images ? 1 : 0
  name                = "${local.gpu_ami_prefix}-${substr(talos_image_factory_schematic.gpu[0].id, 0, 12)}"
  virtualization_type = "hvm"
  architecture        = "x86_64"
  boot_mode           = "uefi"
  ena_support         = true
  imds_support        = "v2.0"
  root_device_name    = "/dev/xvda"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = aws_ebs_snapshot_import.gpu[0].id
    volume_type           = "gp3"
    delete_on_termination = true
  }
}
