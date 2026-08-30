# Environment name is set via GitHub Actions: TF_VAR_env
# Proxmox credentials come from Vault (TF_VAR_proxmox_*).
# IPs: env/dev/network.json.

# Destroy the RKE2 cluster before applying if you reuse these VM IDs and IPs.

vm_node_name    = "pve"
vm_datastore_id = "truenas"
vm_bridge       = "vmbr1"
vm_ip_gateway   = "10.69.0.1"
dns_server      = "10.69.0.1"

k8s_cpu_cores    = 4
k8s_cpu_type     = "x86-64-v2-AES"
k8s_memory_mb    = 8196
k8s_disk_size_gb = 64
k8s_datastore_id = "local-lvm"

longhorn_cpu_cores    = 2
longhorn_cpu_type     = "x86-64-v2-AES"
longhorn_memory_mb    = 4096
longhorn_disk_size_gb = 300
longhorn_datastore_id = "local-lvm"

talos_version = "v1.12.6"
