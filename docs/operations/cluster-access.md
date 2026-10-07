# Cluster access

[Documentation home](../../README.md) · [GitOps architecture](../architecture/gitops.md)

Fetch the environment's access files from Doppler, then point `kubectl` and `talosctl` at those files. Run from `devenv shell` with a Doppler login and network access to the private cluster addresses.

## Select an environment

Start at the repository root:

```bash
export CLUSTER_ENV=dev  # use prod for production
umask 077
mkdir -p "$HOME/.kube" "$HOME/.talos"

doppler secrets get KUBECONFIG --plain \
  --project talos-proxmox --config "$CLUSTER_ENV" \
  > "$HOME/.kube/talos-${CLUSTER_ENV}.yaml"
doppler secrets get TALOSCONFIG --plain \
  --project talos-proxmox --config "$CLUSTER_ENV" \
  > "$HOME/.talos/config-${CLUSTER_ENV}.yaml"
chmod 600 "$HOME/.kube/talos-${CLUSTER_ENV}.yaml" "$HOME/.talos/config-${CLUSTER_ENV}.yaml"

export KUBECONFIG="$HOME/.kube/talos-${CLUSTER_ENV}.yaml"
export TALOSCONFIG="$HOME/.talos/config-${CLUSTER_ENV}.yaml"
kubectl get nodes -o wide
```

Run both downloads successfully before continuing. The cluster root writes these configs; downloading them does not require access to Terraform state.

## Kubernetes versus Talos endpoints

| Environment | Kubernetes API VIP | Example Talos control-plane endpoint | Argo CD UI |
| --- | --- | --- | --- |
| dev | `10.69.11.10:6443` | `10.69.11.11` | <http://10.69.11.254> |
| prod | `10.69.12.10:6443` | `10.69.12.11` | <http://10.69.12.254> |

`kubectl` uses the VIP in the kubeconfig. `talosctl` targets a control-plane **node IP**, not the VIP. The inventory contains the complete list of addresses:

```bash
CONTROL_PLANE_IP="$(jq -r \
  '[to_entries[] | select(.value.role == "servers") | .value.address | split("/")[0]] | sort | first' \
  "terraform/cluster/env/${CLUSTER_ENV}/k8s_nodes.json")"
talosctl --endpoints "$CONTROL_PLANE_IP" --nodes "$CONTROL_PLANE_IP" version
```

The Kubernetes VIP depends on the control plane and etcd. Node-level Talos access is useful when Kubernetes itself is unavailable.

## Open Argo CD

Open the selected environment's UI above after Cilium assigns and announces its LoadBalancer IP. The UI does not depend on Istio or Cloudflare. For initial bootstrap, use `kubectl -n argo-cd port-forward svc/argo-cd-argocd-server 8080:80` and open `http://localhost:8080` until the IP is available. Each environment manages only its local cluster. Retrieve the initial admin password locally:

```bash
kubectl -n argo-cd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Log in as `admin`. This command prints a credential; do not place its output in logs or documentation. If the initial Secret was removed or the password changed, use the current admin credential instead.

## Check convergence

```bash
kubectl -n argo-cd get applications
kubectl get clustersecretstore doppler
kubectl get externalsecrets -A
kubectl get storageclass
kubectl -n istio-system get deploy istiod
kubectl -n istio-system get daemonset istio-cni-node ztunnel
kubectl -n argo-cd get svc argocd-ui
# Prod only: kubectl -n observability get svc grafana-ui
```

Expected results: the root and child Applications are Synced/Healthy; the Doppler store and ExternalSecrets are Ready; Istio control plane and node agents are ready; and there is exactly one default StorageClass, `local-path`. `kubectl get nodes` lists only the Proxmox control-plane nodes (one in dev, `prod-server1` through `prod-server3` in prod) plus any AWS workers; the control-plane nodes also run workloads, and `prod-server1` is prod's SSD-backed node for write-heavy volumes.

## Observability

Prod holds the only telemetry store; both environments' agents send to it.

| Endpoint | Address |
| --- | --- |
| Grafana (prod) | <http://10.69.12.128> |
| OTLP from workloads, in either cluster | `otel-agent.observability.svc:4317` (gRPC) or `:4318` (HTTP) |
| OTLP gateway on the LAN (prod) | `10.69.12.129:4317` / `:4318`, requires `Authorization: Bearer <OTEL_INGEST_TOKEN>` |

Workloads send OTLP to their node's agent without credentials; the agent adds `k8s.cluster.name` and `deployment.environment` and forwards to the gateway. Filter by `deployment.environment` in Grafana to separate dev and prod. Telemetry is kept for 7 days.

Log in to Grafana as `admin` with the generated password; sign-up and anonymous access are disabled:

```bash
doppler secrets get GRAFANA_ADMIN_PASSWORD --plain --project talos-proxmox --config prod
```

Grafana keeps no state of its own. The ClickHouse data source and the dashboards in the `ClickHouse` folder are provisioned from [`apps/components/observability`](../../apps/components/observability/) on every start, and a restart discards sessions and anything edited in the UI. Change dashboards by editing their JSON in `dashboards/` and merging. Queries run as the read-only ClickHouse `app` user, limited to 512 MiB and 60 seconds each.

## Find the failing layer

| Symptom | Start here |
| --- | --- |
| CI cannot reach Proxmox or the API | Tailscale step, routes, and `tag:ci` access; [CI architecture](../architecture/terraform-ci.md) |
| Platform apply fails API readiness or times out installing Argo CD | API `/readyz`, connectivity, and Argo CD pod events; see [apply behavior](../architecture/terraform-ci.md#what-a-successful-apply-means) |
| Application OutOfSync or Degraded | Application sync result and resource events in the local Argo CD UI |
| ExternalSecret not Ready | `kubectl describe externalsecret <name> -n <namespace>` and Doppler store status |
| Istio node agents Pending | Privileged istio-system namespace, host CNI paths, and node events |
| AWS workload stays Pending | [AWS worker operations](aws-burst-workers.md#observe-scaling) |

## Recover configs from an initialized cluster root

Doppler is the usual source. If you already have the correct cluster workspace initialized and need its outputs, run from the repository root:

```bash
export TF_WORKSPACE="talos-cluster-${CLUSTER_ENV}"
umask 077
tofu -chdir=terraform/cluster output -raw kubeconfig > "$KUBECONFIG"
tofu -chdir=terraform/cluster output -raw talosconfig > "$TALOSCONFIG"
```
