#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${ENV_NAME:?ENV_NAME is required}"
INVENTORY="${APPS_ROOT}/../terraform/cluster/env/${ENV_NAME}/k8s_nodes.json"
LONGHORN_NODES="$(jq '[.[] | select(.role == "longhorn")] | length' "${INVENTORY}")"

require_secrets() {
  if [[ "${ENV_NAME}" == dev || "${ENV_NAME}" == prod ]]; then
    : "${CLOUDFLARE_TUNNEL_TOKEN:?CLOUDFLARE_TUNNEL_TOKEN is required for dev/prod}"
    : "${AUTOSCALER_AWS_ACCESS_KEY_ID:?AUTOSCALER_AWS_ACCESS_KEY_ID is required for dev/prod}"
    : "${AUTOSCALER_AWS_SECRET_ACCESS_KEY:?AUTOSCALER_AWS_SECRET_ACCESS_KEY is required for dev/prod}"
  fi
  if (( LONGHORN_NODES > 0 )); then
    : "${LONGHORN_AWS_ENDPOINTS:?LONGHORN_AWS_ENDPOINTS is required}"
    : "${LONGHORN_AWS_ACCESS_KEY_ID:?LONGHORN_AWS_ACCESS_KEY_ID is required}"
    : "${LONGHORN_AWS_SECRET_ACCESS_KEY:?LONGHORN_AWS_SECRET_ACCESS_KEY is required}"
  fi
}

wait_for_cluster() {
  echo "Waiting for Kubernetes API..."
  until kubectl get --raw=/readyz >/dev/null 2>&1; do
    sleep 5
  done

  local expected_nodes
  expected_nodes="$(jq 'length' "${INVENTORY}")"
  echo "Waiting for ${expected_nodes} nodes to register..."
  until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c . || true)" -ge "${expected_nodes}" ]; do
    sleep 5
  done
}

install_gateway_api() {
  local gateway_api_version
  gateway_api_version="$(jq -er .version "${COMPONENTS}/gateway-api/release.json")"
  echo "Installing Gateway API CRDs ${gateway_api_version}"
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${gateway_api_version}/standard-install.yaml"
  kubectl wait --for=condition=Established --timeout=2m \
    crd/gatewayclasses.gateway.networking.k8s.io \
    crd/gateways.gateway.networking.k8s.io \
    crd/httproutes.gateway.networking.k8s.io
}

install_cilium() {
  echo "Installing Cilium (CNI first; SPIRE waits for a StorageClass)"
  privileged_ns cilium-spire
  helm_component cilium 15m
  kubectl -n kube-system rollout status ds/cilium --timeout=10m
  kubectl wait --for=condition=Established --timeout=5m \
    crd/ciliumloadbalancerippools.cilium.io \
    crd/ciliuml2announcementpolicies.cilium.io
  kubectl apply -f "${COMPONENTS}/cilium/environments/${ENV_NAME}/network.yaml"

  echo "Waiting for nodes to become Ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=15m
}

install_storage() {
  if (( LONGHORN_NODES > 0 )); then
    echo "Installing Longhorn"
    privileged_ns longhorn-system
    kubectl create secret generic longhorn-minio-credentials \
      --namespace longhorn-system \
      --from-literal=AWS_ENDPOINTS="${LONGHORN_AWS_ENDPOINTS}" \
      --from-literal=AWS_ACCESS_KEY_ID="${LONGHORN_AWS_ACCESS_KEY_ID}" \
      --from-literal=AWS_SECRET_ACCESS_KEY="${LONGHORN_AWS_SECRET_ACCESS_KEY}" \
      --dry-run=client -o yaml | kubectl apply -f -
    helm_component longhorn 15m --wait
    kubectl apply -f "${COMPONENTS}/longhorn/resources/storage.yaml"
    kubectl apply -f "${COMPONENTS}/longhorn/environments/${ENV_NAME}/ingress.yaml"
  else
    echo "Installing local-path-provisioner"
    privileged_ns local-path-storage
    helm_component local-path-provisioner 5m --wait
  fi
}

install_cloudflare_tunnel() {
  if [[ "${ENV_NAME}" != dev && "${ENV_NAME}" != prod ]]; then
    return
  fi
  echo "Provisioning Cloudflare Tunnel token"
  kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic cloudflare-tunnel-token \
    --namespace cloudflare-tunnel \
    --from-literal=token="${CLOUDFLARE_TUNNEL_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

install_autoscaler_credentials() {
  if [[ "${ENV_NAME}" != dev && "${ENV_NAME}" != prod ]]; then
    return
  fi
  kubectl create namespace cluster-autoscaler --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic cluster-autoscaler-aws \
    --namespace cluster-autoscaler \
    --from-literal=AWS_ACCESS_KEY_ID="${AUTOSCALER_AWS_ACCESS_KEY_ID}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${AUTOSCALER_AWS_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
}

install_gpu_support() {
  if ! jq -e 'any(.[]; (.pci // []) | length > 0)' "${INVENTORY}" >/dev/null; then
    return
  fi
  echo "Installing NVIDIA GPU Operator and DRA driver"
  privileged_ns gpu-operator
  helm_component gpu-operator 15m --wait
  privileged_ns nvidia-dra-driver-gpu
  helm_component nvidia-dra-driver 15m --wait
}

require_secrets
wait_for_cluster
install_gateway_api
install_cilium
install_storage

echo "Waiting for Cilium (including SPIRE) to become ready..."
helm_component cilium 15m --wait

echo "Installing metrics-server"
helm_component metrics-server 5m --wait

install_cloudflare_tunnel
install_autoscaler_credentials
install_gpu_support

echo "Bootstrap complete."
