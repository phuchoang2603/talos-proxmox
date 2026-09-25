# Cluster access with talosctl

Use Talos client credentials for both the Talos API and kubectl.

`talosctl` must target **control-plane node IPs**, not the Kubernetes VIP. The VIP is only for kube-apiserver and depends on etcd.

GitHub Actions (and a laptop `tofu apply` plus `doppler secrets set`) write cluster-admin files to Doppler as `TALOSCONFIG` and `KUBECONFIG`. You do not need OpenTofu state or GitHub Actions artifacts on your machine.

## From Doppler (usual path)

```bash
doppler login
# default config is dev (.doppler.yaml); use --config prod or --config argocd for those clusters

doppler secrets get TALOSCONFIG --plain > talosconfig
doppler secrets get KUBECONFIG --plain > kubeconfig
chmod 600 talosconfig kubeconfig
export TALOSCONFIG="$PWD/talosconfig" KUBECONFIG="$PWD/kubeconfig"

talosctl --nodes 10.69.11.11 version
kubectl get nodes
```

Node IPs are in `terraform/cluster/env/{env}/k8s_nodes.json` (`role` `servers`).

You can also mint a kubeconfig from Talos itself:

```bash
talosctl --nodes 10.69.11.11 kubeconfig ./kubeconfig
```

Treat `talosconfig` and `kubeconfig` as secrets. They are already gitignored.

## From OpenTofu (optional)

If you just applied provision locally and still have the workspace initialized:

```bash
cd terraform/cluster
tofu output -raw talosconfig > ../../talosconfig
tofu output -raw kubeconfig > ../../kubeconfig
```
