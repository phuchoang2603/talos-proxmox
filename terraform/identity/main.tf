terraform {
  required_version = ">= 1.12.5, < 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:phuchoang2603@91061595/talos-proxmox@1351657631:environment:dev",
        "repo:phuchoang2603@91061595/talos-proxmox@1351657631:environment:prod",
      ]
    }
  }
}

resource "aws_iam_policy" "ci" {
  name = "talos-proxmox-ci"
  policy = replace(
    file("${path.module}/ci-policy.json"),
    "ACCOUNT_ID", data.aws_caller_identity.current.account_id
  )
}

resource "aws_iam_policy" "ci_iam" {
  name = "talos-proxmox-ci-iam"
  policy = replace(
    file("${path.module}/ci-iam-policy.json"),
    "ACCOUNT_ID", data.aws_caller_identity.current.account_id
  )
}

resource "aws_iam_role" "ci" {
  name                 = "talos-proxmox-ci"
  max_session_duration = 7200
  assume_role_policy   = data.aws_iam_policy_document.github_actions.json
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci.arn
}

resource "aws_iam_role_policy_attachment" "ci_iam" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci_iam.arn
}

output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}
