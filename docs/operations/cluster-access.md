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

Run both downloads successfully before continuing. The cluster root writes these configs; downloading them does not require access to Terraform state. Dev exists only after an operator builds it with **Manual Provision**, and its configs are removed when it is destroyed, so download them again after each rebuild.

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
# Prod only: kubectl -n observability get svc grafana
```

Expected results: the root and child Applications are Synced/Healthy; the Doppler store and ExternalSecrets are Ready; Istio control plane and node agents are ready; and there is exactly one default StorageClass, `local-path`. `kubectl get nodes` lists only the Proxmox control-plane nodes (one in dev, `prod-server1` through `prod-server3` in prod) plus any AWS workers; the control-plane nodes also run workloads, and `prod-server1` is prod's SSD-backed node for write-heavy volumes.

## Observability

Only prod collects telemetry; dev runs no telemetry components.

| Endpoint | Address |
| --- | --- |
| Grafana (prod) | <https://grafana.phuchoang.sbs>; LAN service <http://10.69.12.128> |
| OTLP metrics (HTTP/protobuf) | `http://vmagent-vmks.observability.svc:8429/opentelemetry/v1/metrics` |
| OTLP traces (HTTP/protobuf) | `http://vtagent-vmks.observability.svc:10429/insert/opentelemetry/v1/traces` |
| OTLP logs (HTTP/protobuf) | `http://vlsingle-vmks.observability.svc:9428/insert/opentelemetry/v1/logs` |

Workloads export cumulative OTLP metrics and traces to VMAgent and VTAgent at their per-signal HTTP endpoints. There are no OpenTelemetry collectors, agents, or gateways. VMAgent scrapes cluster metrics every 60 seconds, and VLAgent collects container logs from all nodes, including AWS workers. Kubernetes scheduler, controller-manager, etcd, and kube-proxy scrapes are disabled because Talos does not expose the default endpoints.

VMAgent and VTAgent run on `prod-server2` with separate 1 GiB local-path queue volumes, each capped at 513 MiB per destination (the smallest whole-MiB limit supported by the agents). They buffer during store outages and replay queued data when storage returns; queues survive pod restarts. Losing the queue disk loses buffered telemetry, and filling a queue drops its oldest data. This does not replicate stored telemetry.

VictoriaMetrics, VictoriaLogs, and VictoriaTraces retain telemetry for 3 days on separate local-path volumes on `prod-server1`. Each reserves 20 GiB of free disk space. Telemetry is not backed up or exported to S3; RustFS archive cleanup is performed separately. Grafana provisions the three data sources, trace-to-log links, and the stack's Kubernetes and Victoria dashboards. Its application state uses a local-path volume on the same node.

## Public URLs (prod)

The prod Cloudflare tunnel publishes three hostnames. Cloudflare terminates TLS and redirects `http://` to HTTPS.

| URL | Service | Login |
| --- | --- | --- |
| <https://auth.phuchoang.sbs/dex> | Dex, the shared login | The Dex user (`identity.email` in [`apps/components/auth/values.yaml`](../../apps/components/auth/values.yaml)) and `AUTH_DEX_PASSWORD` |
| <https://kubeflow.phuchoang.sbs> | Kubeflow Dashboard, through the Istio ingress gateway | Redirects to Dex; see [Kubeflow](kubeflow.md) |
| <https://grafana.phuchoang.sbs> | Grafana | Dex or the local admin account |

Grafana grants the configured operator email an Admin role through Dex and rejects unmapped identities. The public tunnel and LAN service both require login. The local account is `admin`, with `GRAFANA_ADMIN_PASSWORD` from prod Doppler; anonymous access and password sign-up are disabled.

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
