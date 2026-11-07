resource "terraform_data" "storage_cleanup" {
  input = {
    project_id   = var.project_id
    cluster_name = var.cluster_name
  }
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    environment = {
      PROJECT_ID = self.input.project_id
      CLUSTER    = self.input.cluster_name
    }
    command = <<-EOT
      set -euo pipefail
      if [ "$${PURGE_DATA:-false}" != true ]; then
        echo "Retaining persistent disks and snapshots for $CLUSTER"
        exit 0
      fi
      gcloud compute disks list --project="$PROJECT_ID" \
        --filter="labels.platform-cluster=$CLUSTER" --format=json |
        jq -r '.[] | [.name, (.zone // .region)] | @tsv' |
        while IFS=$'\t' read -r disk location; do
          case "$location" in
            */zones/*) gcloud compute disks delete "$disk" --project="$PROJECT_ID" --zone="$${location##*/}" --quiet ;;
            */regions/*) gcloud compute disks delete "$disk" --project="$PROJECT_ID" --region="$${location##*/}" --quiet ;;
            *) echo "Unrecognized disk location" >&2; exit 1 ;;
          esac
        done
      gcloud compute snapshots list --project="$PROJECT_ID" \
        --filter="labels.platform-cluster=$CLUSTER" --format='value(name)' |
        while IFS= read -r snapshot; do
          [ -n "$snapshot" ] || continue
          gcloud compute snapshots delete "$snapshot" --project="$PROJECT_ID" --quiet
        done
    EOT
  }
  depends_on = [google_compute_network.cluster]
}
