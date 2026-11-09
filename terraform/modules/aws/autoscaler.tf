resource "aws_iam_user" "autoscaler" {
  name = "${var.cluster_name}-autoscaler"
  tags = local.tags
}
resource "aws_iam_access_key" "autoscaler" { user = aws_iam_user.autoscaler.name }
resource "aws_iam_user_policy" "autoscaler" {
  name = "cluster-worker-groups"
  user = aws_iam_user.autoscaler.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances", "autoscaling:DescribeLaunchConfigurations", "autoscaling:DescribeScalingActivities", "autoscaling:DescribeTags", "ec2:DescribeImages", "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplateVersions", "ec2:GetInstanceTypesFromInstanceRequirements"], Resource = "*" },
      { Effect = "Allow", Action = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"], Resource = [for group in aws_autoscaling_group.worker : group.arn] },
    ]
  })
}
