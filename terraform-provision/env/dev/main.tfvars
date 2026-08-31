# Environment name is set via GitHub Actions: TF_VAR_env
# Proxmox credentials come from Vault (TF_VAR_proxmox_*).
# Node sizing lives in env/dev/{k8s,longhorn,gpu}_nodes.json.

vm_node_name    = "pve"
vm_datastore_id = "truenas"
vm_bridge       = "vmbr1"
vm_ip_gateway   = "10.69.0.1"
dns_server      = "10.69.0.1"

talos_version = "v1.13.9"
