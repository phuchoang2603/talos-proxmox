# Cluster access with talosctl

Use Talos client credentials for both the Talos API and kubectl. There is no Vault OIDC / kubelogin path.

`talosctl` must target **control-plane node IPs**, not the Kubernetes VIP. The VIP is only for kube-apiserver and depends on etcd.

GitHub Actions (and a laptop `terraform apply`) write cluster-admin files to Vault as **`kv/{env}/talos`** (`talosconfig` and `kubeconfig` fields). You do not need Terraform state or GitHub Actions artifacts on your machine.

Admins can read this path. Developer Vault policies deny it.

## From Vault (usual path)

```bash
export VAULT_ADDR="https://your-vault-address"
vault login

vault kv get -field=talosconfig kv/dev/talos > talosconfig
vault kv get -field=kubeconfig kv/dev/talos > kubeconfig
chmod 600 talosconfig kubeconfig
export TALOSCONFIG="$PWD/talosconfig" KUBECONFIG="$PWD/kubeconfig"

talosctl --nodes 10.69.1.111 version
kubectl get nodes
```

Use `kv/prod/talos` for prod. Node IPs are in `terraform-provision/env/{env}/k8s_nodes.json` (`role` `servers`).

You can also mint a kubeconfig from Talos itself:

```bash
talosctl --nodes 10.69.1.111 kubeconfig ./kubeconfig
```

Treat `talosconfig` and `kubeconfig` as secrets. They are already gitignored.

## From Terraform (optional)

If you just applied provision locally and still have the workspace initialized:

```bash
cd terraform-provision
terraform output -raw talosconfig > ../talosconfig
terraform output -raw kubeconfig > ../kubeconfig
```
