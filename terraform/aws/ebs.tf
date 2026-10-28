resource "aws_iam_user" "ebs" {
  count = var.create_controlplane ? 1 : 0
  name  = "platform-${var.env}-ebs-csi"
  tags  = local.tags
}
resource "aws_iam_access_key" "ebs" {
  count = var.create_controlplane ? 1 : 0
  user  = aws_iam_user.ebs[0].name
}
resource "aws_iam_user_policy" "ebs" {
  count      = var.create_controlplane ? 1 : 0
  depends_on = [terraform_data.storage_cleanup]
  name       = "environment-volumes"
  user       = aws_iam_user.ebs[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:DescribeAvailabilityZones", "ec2:DescribeInstances", "ec2:DescribeInstanceTypes", "ec2:DescribeSnapshots", "ec2:DescribeTags", "ec2:DescribeVolumes", "ec2:DescribeVolumesModifications", "ec2:DescribeVolumeStatus"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:CreateVolume"], Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/*", Condition = { StringEquals = { "aws:RequestTag/platform-cluster" = var.cluster_name } } },
      { Effect = "Allow", Action = ["ec2:CreateVolume"], Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot/*" },
      { Effect = "Allow", Action = ["ec2:AttachVolume", "ec2:DetachVolume", "ec2:DeleteVolume", "ec2:ModifyVolume", "ec2:CreateSnapshot", "ec2:DeleteTags"], Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/*", Condition = { StringEquals = { "ec2:ResourceTag/platform-cluster" = var.cluster_name } } },
      { Effect = "Allow", Action = ["ec2:AttachVolume", "ec2:DetachVolume"], Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*", Condition = { StringEquals = { "ec2:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" } } },
      { Effect = "Allow", Action = ["ec2:CreateTags"], Resource = ["arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:volume/*", "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot/*"], Condition = { StringEquals = { "ec2:CreateAction" = ["CreateVolume", "CreateSnapshot"] } } },
      { Effect = "Allow", Action = ["ec2:CreateSnapshot"], Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot/*", Condition = { StringEquals = { "aws:RequestTag/platform-cluster" = var.cluster_name } } },
      { Effect = "Allow", Action = ["ec2:DeleteSnapshot"], Resource = "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:snapshot/*", Condition = { StringEquals = { "ec2:ResourceTag/platform-cluster" = var.cluster_name } } }
    ]
  })
}
output "ebs_access_key_id" {
  value     = one(aws_iam_access_key.ebs[*].id)
  sensitive = true
}
output "ebs_secret_access_key" {
  value     = one(aws_iam_access_key.ebs[*].secret)
  sensitive = true
}
