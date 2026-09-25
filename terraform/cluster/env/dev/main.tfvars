# Environment name is set via GitHub Actions: TF_VAR_env
# Proxmox credentials come from Doppler (`PROXMOX_*`, mapped to TF_VAR_proxmox_*).
# Node sizing lives in env/dev/k8s_nodes.json.

vm_node_name    = "pve"
vm_datastore_id = "truenas"
vm_bridge       = "vmbr1"
vm_ip_gateway   = "10.69.0.1"
dns_server      = "10.69.0.1"

talos_version      = "v1.13.9"
kubernetes_version = "v1.36.3"

# Official Talos v1.13.9 amd64 AMI in us-east-1.
aws_ami_id = "ami-09b2293881e8b9139"
