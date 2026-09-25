data "aws_caller_identity" "current" {}

resource "aws_iam_user" "autoscaler" {
  name = "talos-proxmox-autoscaler-${var.env}"
  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_policy" "autoscaler" {
  name = "talos-proxmox-autoscaler-${var.env}"
  policy = replace(replace(
    file("${path.module}/iam/autoscaler-policy.json"),
    "ACCOUNT_ID", data.aws_caller_identity.current.account_id
  ), "ENV", var.env)
  tags = local.tags
}

resource "aws_iam_user_policy_attachment" "autoscaler" {
  user       = aws_iam_user.autoscaler.name
  policy_arn = aws_iam_policy.autoscaler.arn
}
