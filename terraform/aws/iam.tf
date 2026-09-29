data "aws_caller_identity" "current" {}

# Worker instances carry this profile only so Karpenter can launch them. It grants no permissions.
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
  name               = "${local.name}-worker"
  assume_role_policy = data.aws_iam_policy_document.worker_trust.json
  tags               = local.tags
}

resource "aws_iam_instance_profile" "worker" {
  name = "${local.name}-worker"
  role = aws_iam_role.worker.name
  tags = local.tags
}

resource "aws_iam_user" "karpenter" {
  name = "talos-proxmox-karpenter-${var.env}"
  tags = local.tags
}

resource "aws_iam_policy" "karpenter" {
  name = "talos-proxmox-karpenter-${var.env}"
  policy = replace(replace(replace(replace(replace(
    file("${path.module}/iam/karpenter-policy.json"),
    "ACCOUNT_ID", data.aws_caller_identity.current.account_id),
    "REGION", var.region),
    "CLUSTER", var.cluster_name),
    "AMI_ID", var.ami_id),
    "WORKER_PROFILE", aws_iam_role.worker.name
  )
  tags = local.tags
}

resource "aws_iam_access_key" "karpenter" {
  user = aws_iam_user.karpenter.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_user_policy_attachment" "karpenter" {
  user       = aws_iam_user.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn

  # Destroyed before the sweep, so the controller cannot launch while its instances are terminated.
  depends_on = [terraform_data.karpenter_sweep]
}
