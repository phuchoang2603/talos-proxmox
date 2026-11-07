resource "terraform_data" "storage_cleanup" {
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
    command = <<-EOT
      set -euo pipefail
      if [ "$${PURGE_DATA:-false}" != true ]; then
        echo "Retaining tagged persistent volumes and snapshots for $CLUSTER"
        exit 0
      fi
      for selector in "Name=tag:platform-cluster,Values=$CLUSTER" "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned"; do
        ids=$(aws ec2 describe-volumes --filters "$selector" --query 'Volumes[].VolumeId' --output text)
        for id in $ids; do
          aws ec2 wait volume-available --volume-ids "$id"
          aws ec2 delete-volume --volume-id "$id"
        done
      done
      ids=$(aws ec2 describe-snapshots --owner-ids self --filters "Name=tag:platform-cluster,Values=$CLUSTER" --query 'Snapshots[].SnapshotId' --output text)
      for id in $ids; do
        aws ec2 delete-snapshot --snapshot-id "$id"
      done
    EOT
  }
  depends_on = [aws_vpc.worker]
}
