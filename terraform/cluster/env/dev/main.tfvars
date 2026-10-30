# Environment name is set via GitHub Actions: TF_VAR_env
# Proxmox credentials are read from Doppler (`PROXMOX_*`) through the Doppler provider.
# Node sizing lives in env/dev/k8s_nodes.json.

vm_node_name    = "pve"
vm_datastore_id = "truenas"
vm_bridge       = "vmbr1"
vm_ip_gateway   = "10.69.0.1"
dns_server      = "10.69.0.1"

talos_version      = "v1.14.5"
kubernetes_version = "v1.37.2"

aws_ami_id             = "ami-09b2293881e8b9139"
aws_vpc_cidr           = "10.80.0.0/16"
aws_availability_zones = ["us-east-1a"]
