locals {
  ml_prefix_arns = {
    datasets = "${aws_s3_bucket.ml.arn}/datasets/*"
    runs     = "${aws_s3_bucket.ml.arn}/runs/*"
    outputs  = "${aws_s3_bucket.ml.arn}/runs/*/outputs/*"
  }
}

resource "aws_iam_user" "ml_issuer" {
  name = "talos-proxmox-ml-issuer"
}

resource "aws_iam_access_key" "ml_issuer" {
  user = aws_iam_user.ml_issuer.name
}

data "aws_iam_policy_document" "ml_role_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.ml_issuer.arn]
    }
  }
}

resource "aws_iam_role" "ml_reader" {
  name                 = "talos-proxmox-ml-reader"
  assume_role_policy   = data.aws_iam_policy_document.ml_role_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "ml_writer" {
  name                 = "talos-proxmox-ml-writer"
  assume_role_policy   = data.aws_iam_policy_document.ml_role_trust.json
  max_session_duration = 43200
}

resource "aws_iam_role" "ml_transfer" {
  name                 = "talos-proxmox-ml-transfer"
  assume_role_policy   = data.aws_iam_policy_document.ml_role_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ml_reader" {
  statement {
    actions   = ["s3:GetObject"]
    resources = [local.ml_prefix_arns.datasets]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ml.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["datasets/*"]
    }
  }
}

data "aws_iam_policy_document" "ml_writer" {
  statement {
    actions   = ["s3:GetObject"]
    resources = [local.ml_prefix_arns.datasets]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = [local.ml_prefix_arns.runs]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ml.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["datasets/*", "runs/*"]
    }
  }
}

data "aws_iam_policy_document" "ml_transfer" {
  statement {
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = [local.ml_prefix_arns.datasets]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = [local.ml_prefix_arns.outputs]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.ml.arn]
  }
}

resource "aws_iam_role_policy" "ml_reader" {
  name   = "s3-datasets-read"
  role   = aws_iam_role.ml_reader.id
  policy = data.aws_iam_policy_document.ml_reader.json
}

resource "aws_iam_role_policy" "ml_writer" {
  name   = "s3-run-write"
  role   = aws_iam_role.ml_writer.id
  policy = data.aws_iam_policy_document.ml_writer.json
}

resource "aws_iam_role_policy" "ml_transfer" {
  name   = "s3-transfer"
  role   = aws_iam_role.ml_transfer.id
  policy = data.aws_iam_policy_document.ml_transfer.json
}

data "aws_iam_policy_document" "ml_issuer" {
  statement {
    actions = ["sts:AssumeRole"]
    resources = [
      aws_iam_role.ml_reader.arn,
      aws_iam_role.ml_writer.arn,
      aws_iam_role.ml_transfer.arn,
    ]
  }
}

resource "aws_iam_user_policy" "ml_issuer" {
  name   = "assume-ml-roles"
  user   = aws_iam_user.ml_issuer.name
  policy = data.aws_iam_policy_document.ml_issuer.json
}

resource "doppler_secret" "ml_storage" {
  for_each = {
    ML_BUCKET                       = aws_s3_bucket.ml.id
    ML_REGION                       = "us-east-1"
    ML_READER_ROLE_ARN              = aws_iam_role.ml_reader.arn
    ML_WRITER_ROLE_ARN              = aws_iam_role.ml_writer.arn
    ML_TRANSFER_ROLE_ARN            = aws_iam_role.ml_transfer.arn
    ML_ISSUER_AWS_ACCESS_KEY_ID     = aws_iam_access_key.ml_issuer.id
    ML_ISSUER_AWS_SECRET_ACCESS_KEY = aws_iam_access_key.ml_issuer.secret
  }

  project = doppler_project.this.name
  config  = doppler_environment.this["prod"].slug
  name    = each.key
  value   = each.value
}
