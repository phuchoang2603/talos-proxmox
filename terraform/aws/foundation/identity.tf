resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_iam_role" "ci" {
  name                 = "talos-proxmox-ci"
  max_session_duration = 7200
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:phuchoang2603@91061595/talos-proxmox@1351657631:environment:prod"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "ci" {
  name = "cluster-infrastructure"
  role = aws_iam_role.ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ec2:Describe*", "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute", "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:CreateVpcEndpoint", "ec2:ModifyVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:CreateTags", "ec2:DeleteTags", "ec2:RunInstances", "ec2:TerminateInstances", "ec2:ModifyInstanceAttribute", "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress", "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion", "ec2:DeleteLaunchTemplate", "ec2:DeleteLaunchTemplateVersions", "ec2:ModifyLaunchTemplate", "ec2:DeleteVolume", "ec2:DeleteSnapshot", "autoscaling:Describe*", "autoscaling:CreateAutoScalingGroup", "autoscaling:UpdateAutoScalingGroup", "autoscaling:DeleteAutoScalingGroup", "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.region } } },
      { Effect = "Allow", Action = ["iam:CreateRole", "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListRoleTags", "iam:UpdateAssumeRolePolicy", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:CreateInstanceProfile", "iam:GetInstanceProfile", "iam:DeleteInstanceProfile", "iam:ListInstanceProfileTags", "iam:TagInstanceProfile", "iam:UntagInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:CreateUser", "iam:GetUser", "iam:DeleteUser", "iam:TagUser", "iam:UntagUser", "iam:ListUserPolicies", "iam:ListUserTags", "iam:ListAttachedUserPolicies", "iam:ListGroupsForUser", "iam:CreateAccessKey", "iam:ListAccessKeys", "iam:DeleteAccessKey", "iam:PutUserPolicy", "iam:GetUserPolicy", "iam:DeleteUserPolicy"], Resource = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/prod-talos-*", "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/prod-talos-*", "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/prod-talos-*"] },
      { Effect = "Allow", Action = "iam:PassRole", Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/prod-talos-worker", Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } } },
    ]
  })
}
resource "aws_iam_service_linked_role" "autoscaling" { aws_service_name = "autoscaling.amazonaws.com" }
resource "aws_iam_service_linked_role" "spot" { aws_service_name = "spot.amazonaws.com" }
