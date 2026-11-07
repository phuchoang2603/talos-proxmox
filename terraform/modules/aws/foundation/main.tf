terraform {
  required_providers {
    aws   = { source = "hashicorp/aws" }
    talos = { source = "siderolabs/talos" }
  }
}

variable "region" { type = string }
variable "talos_version" { type = string }
variable "ami_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "AWS foundation requires a Talos AMI matching talos_version in the selected region."
  }
}
variable "enable_gpu_images" {
  type    = bool
  default = false
}

data "aws_caller_identity" "current" {}
locals {
  image_bucket_name  = "talos-proxmox-images-${data.aws_caller_identity.current.account_id}-${var.region}"
  object_bucket_name = "talos-proxmox-prod-platform-${data.aws_caller_identity.current.account_id}-${var.region}"
  object_consumers   = toset(["gateway", "artifacts", "substrate"])
  object_prefixes = {
    gateway   = ["datasets/payment-gateway/", "runs/payment-gateway/", "lakehouse/"]
    artifacts = ["artifacts/", "datasets/", "runs/"]
    substrate = ["substrate/"]
  }
}

output "ci_variables" {
  value = {
    AWS_CI_ROLE_ARN = aws_iam_role.ci.arn
    AWS_REGION      = var.region
  }
}
output "secrets" {
  value = merge({
    TALOS_IMAGE_ID          = var.ami_id
    OBJECT_STORAGE_BUCKET   = aws_s3_bucket.platform.id
    OBJECT_STORAGE_ENDPOINT = "https://s3.${var.region}.amazonaws.com"
    OBJECT_STORAGE_REGION   = var.region
    OBJECT_ARTIFACTS_BUCKET = aws_s3_bucket.platform.id
    OBJECT_SUBSTRATE_BUCKET = aws_s3_bucket.platform.id
    }, [for consumer in local.object_consumers : {
      "OBJECT_${upper(consumer)}_ACCESS_KEY_ID"     = aws_iam_access_key.objects[consumer].id
      "OBJECT_${upper(consumer)}_SECRET_ACCESS_KEY" = aws_iam_access_key.objects[consumer].secret
  }]...)
  sensitive = true
}
