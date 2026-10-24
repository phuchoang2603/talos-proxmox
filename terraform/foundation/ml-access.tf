resource "aws_iam_user" "ml" {
  name = "talos-proxmox-ml"
}

data "aws_iam_policy_document" "ml" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:PutObjectTagging",
    ]
    resources = [
      "${aws_s3_bucket.ml.arn}/datasets/*",
      "${aws_s3_bucket.ml.arn}/runs/*",
    ]
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

resource "aws_iam_user_policy" "ml" {
  name   = "s3-datasets-and-runs"
  user   = aws_iam_user.ml.name
  policy = data.aws_iam_policy_document.ml.json
}

# Rotate with: tofu apply -replace=aws_iam_access_key.ml
resource "aws_iam_access_key" "ml" {
  user = aws_iam_user.ml.name
}

resource "doppler_secret" "ml_storage" {
  for_each = {
    ML_BUCKET                = aws_s3_bucket.ml.id
    ML_AWS_ACCESS_KEY_ID     = aws_iam_access_key.ml.id
    ML_AWS_SECRET_ACCESS_KEY = aws_iam_access_key.ml.secret
  }

  project = doppler_project.this.name
  config  = doppler_environment.this["prod"].slug
  name    = each.key
  value   = each.value
}
