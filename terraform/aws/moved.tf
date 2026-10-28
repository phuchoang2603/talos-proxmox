moved {
  from = aws_eip.controlplane
  to   = aws_eip.controlplane[0]
}

moved {
  from = module.talos
  to   = module.talos[0]
}

moved {
  from = aws_instance.controlplane
  to   = aws_instance.controlplane[0]
}

moved {
  from = aws_eip_association.controlplane
  to   = aws_eip_association.controlplane[0]
}

moved {
  from = talos_machine_configuration_apply.controlplane
  to   = talos_machine_configuration_apply.controlplane[0]
}

moved {
  from = module.bootstrap
  to   = module.bootstrap[0]
}

moved {
  from = aws_iam_user.ebs
  to   = aws_iam_user.ebs[0]
}

moved {
  from = aws_iam_access_key.ebs
  to   = aws_iam_access_key.ebs[0]
}

moved {
  from = aws_iam_user_policy.ebs
  to   = aws_iam_user_policy.ebs[0]
}
