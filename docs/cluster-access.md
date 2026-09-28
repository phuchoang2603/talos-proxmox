# Cluster access with talosctl

Use Talos client credentials for both the Talos API and kubectl.

`talosctl` must target **control-plane node IPs**, not the Kubernetes VIP. The VIP is only for kube-apiserver and depends on etcd.

The cluster OpenTofu root writes cluster-admin files to each environment's Doppler config as `TALOSCONFIG` and `KUBECONFIG`. You do not need OpenTofu state or GitHub Actions artifacts on your machine.

## From Doppler (usual path)

```bash
doppler login
# default config is dev (.doppler.yaml); use --config prod for prod

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

## Argo CD

Each environment runs its own Argo CD in the `argo-cd` namespace. The UI is served over HTTP at the `argo-cd-route` Gateway address: `http://10.69.11.254` for dev and `http://10.69.12.254` for prod. Log in as `admin` with the initial password:

```bash
kubectl -n argo-cd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## From OpenTofu (optional)

If you just applied the cluster root locally and still have the workspace initialized:

```bash
cd terraform/cluster
tofu output -raw talosconfig > ../../talosconfig
tofu output -raw kubeconfig > ../../kubeconfig
```
