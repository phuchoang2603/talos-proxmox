# GitHub Actions Automated Deployment

CI uses GitHub Actions Environments and Doppler for Talos on Proxmox.

## Prerequisites

- [Doppler Setup](./doppler-setup.md)
- Tailscale (GitHub-hosted runners)
- GitHub repository `talos-proxmox`
- Proxmox API access
- MinIO (or S3) for Terraform state

**Do not apply** while the RKE2 cluster still occupies the same VM IDs and IPs.

## Step 1: Update VM Inventory

Edit `terraform-provision/env/{dev,prod,gpu}/k8s_nodes.json`, `longhorn_nodes.json`, and `gpu_nodes.json`. Shape:

```json
{
  "dev-server1": {
    "vm_id": 111,
    "node": "pve",
    "role": "servers",
    "address": "10.69.1.111/16",
    "cpu_cores": 4,
    "cpu_type": "host",
    "memory_mb": 8192,
    "disk_size_gb": 64,
    "datastore_id": "local-lvm"
  }
}
```

`role` `servers` is control plane. `longhorn` and `gpu` (and any other non-`servers` role) are workers. GPU nodes also set `pci` to Proxmox host PCI IDs and boot a second Factory image with NVIDIA production extensions.

Edit `terraform-provision/env/{env}/network.json` for the Talos API VIP and Cilium LoadBalancer pool (`lb_range`). Per-app Gateway LAN IPs live in `apps/manifests/env/{env}/network.yaml` (Hubble), `longhorn-ingress.yaml`, and `argo-ingress.yaml`.

## Step 2: GitHub Environments

Settings → Environments. Create **`dev`**, **`prod`**, and **`gpu`** (same names as `terraform-provision/env/`). You can add required reviewers on `prod`.

Pushes and pull requests against `main` always use **`dev`**. **`prod`** and **`gpu`** are only selected via **Run workflow**.

Optional: store `DOPPLER_TOKEN` as an environment secret (per env) instead of a repository secret. The job reads `secrets.DOPPLER_TOKEN` from the Environment first.

## Step 3: GitHub secret

If not using environment secrets, repository secret:

| Secret | Description |
| --- | --- |
| `DOPPLER_TOKEN` | Doppler read/write service token for that Doppler config |

## Step 4: Deploy

1. **Pull request:** Plans `dev`, comments on the PR. No apply or Helm.
2. **Push to `main`:** Applies `dev`, writes `TALOSCONFIG` / `KUBECONFIG` to Doppler, then `apps/bootstrap.sh`.
3. **Run workflow:** Pick Environment `dev`, `prod`, or `gpu` and action **apply** or **destroy**.

State key: `talos-${environment}.tfstate` (does not overwrite the RKE2 `dev.tfstate` / `prod.tfstate` keys). Doppler config names match (`dev`, `prod`, `gpu`).

## Destroy

Actions → Provision and Bootstrap → Run workflow → environment + **destroy**. Helm is skipped; destroying nodes removes the cluster.

## Next

[Cluster Access](./cluster-access.md)
