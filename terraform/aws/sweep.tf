# Karpenter's instances and launch templates are not in state. On destroy, this removes them through
# the AWS API after the controller's policy is detached and before the network and instance profile
# they use (an internet gateway cannot detach while instances hold public IPs), so the destroy needs
# neither the cluster nor the controller.
# Keep values in `input`, not `triggers_replace`: replacing this resource terminates running workers.
resource "terraform_data" "karpenter_sweep" {
  input = {
    region       = var.region
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    environment = {
      AWS_REGION = self.input.region
      AWS_PAGER  = ""
      CLUSTER    = self.input.cluster_name
    }
    # Keep listing for a minute after the detach, which IAM may take to propagate to the controller.
    command = <<-EOT
      set -euo pipefail
      filters=("Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" "Name=tag-key,Values=karpenter.sh/nodepool")
      start=$SECONDS
      while :; do
        if (( SECONDS - start >= 900 )); then
          echo "Karpenter instances for $CLUSTER still exist after 15 minutes" >&2
          exit 1
        fi
        out=$(aws ec2 describe-instances --filters "$${filters[@]}" \
          "Name=instance-state-name,Values=pending,running,stopping,stopped" \
          --query 'Reservations[].Instances[].[InstanceId]' --output text)
        if [ -n "$out" ]; then
          mapfile -t ids <<< "$out"
          echo "Terminating $${#ids[@]} Karpenter instance(s) for $CLUSTER"
          aws ec2 terminate-instances --instance-ids "$${ids[@]}" > /dev/null
          aws ec2 wait instance-terminated --instance-ids "$${ids[@]}"
        elif (( SECONDS - start >= 60 )); then
          break
        else
          sleep 15
        fi
      done
      out=$(aws ec2 describe-launch-templates --filters "$${filters[@]}" \
        --query 'LaunchTemplates[].[LaunchTemplateId]' --output text)
      if [ -n "$out" ]; then
        mapfile -t lts <<< "$out"
        for lt in "$${lts[@]}"; do
          aws ec2 delete-launch-template --launch-template-id "$lt" > /dev/null
        done
      fi
    EOT
  }

  depends_on = [
    aws_subnet.worker,
    aws_security_group.worker,
    aws_internet_gateway.worker,
    aws_iam_instance_profile.worker,
  ]
}
