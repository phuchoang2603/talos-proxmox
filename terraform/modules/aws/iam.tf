data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "worker_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.cluster_name}-worker"
  assume_role_policy = data.aws_iam_policy_document.worker_trust.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_name}-worker"
  role = aws_iam_role.worker.name
  tags = local.tags
}
