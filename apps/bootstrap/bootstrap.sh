#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${ENV_NAME:?ENV_NAME is required}"
if [[ "${ENV_NAME}" == dev || "${ENV_NAME}" == prod ]]; then
  : "${CLOUDFLARE_TUNNEL_TOKEN:?CLOUDFLARE_TUNNEL_TOKEN is required for dev/prod}"
fi

INV="${APPS_ROOT}/../terraform/cluster/env/${ENV_NAME}"
LONGHORN_NODES="$(jq '[.[] | select(.role == "longhorn")] | length' "${INV}/k8s_nodes.json")"
if [ "${LONGHORN_NODES}" -gt 0 ]; then
  : "${LONGHORN_AWS_ENDPOINTS:?LONGHORN_AWS_ENDPOINTS is required}"
  : "${LONGHORN_AWS_ACCESS_KEY_ID:?LONGHORN_AWS_ACCESS_KEY_ID is required}"
  : "${LONGHORN_AWS_SECRET_ACCESS_KEY:?LONGHORN_AWS_SECRET_ACCESS_KEY is required}"
fi

GATEWAY_API_VERSION="$(component_version gateway-api)"

echo "Waiting for Kubernetes API..."
until kubectl get --raw=/readyz >/dev/null 2>&1; do
  sleep 5
done

expected_nodes="$(jq 'length' "${INV}/k8s_nodes.json")"
echo "Waiting for ${expected_nodes} nodes to register..."
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c . || true)" -ge "${expected_nodes}" ]; do
  sleep 5
done

echo "Installing Gateway API CRDs ${GATEWAY_API_VERSION}"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established --timeout=2m \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io

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

if [ "${LONGHORN_NODES}" -gt 0 ]; then
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

echo "Waiting for Cilium (including SPIRE) to become ready..."
helm_component cilium 15m --wait

echo "Installing metrics-server"
helm_component metrics-server 5m --wait

if [[ "${ENV_NAME}" == dev || "${ENV_NAME}" == prod ]]; then
  echo "Provisioning Cloudflare Tunnel token"
  kubectl create namespace cloudflare-tunnel --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic cloudflare-tunnel-token \
    --namespace cloudflare-tunnel \
    --from-literal=token="${CLOUDFLARE_TUNNEL_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

has_gpu_nodes() {
  jq '[.[] | select((.pci // []) | length > 0)]' "${INV}/k8s_nodes.json"
}

if [ "$(has_gpu_nodes | jq 'length')" -gt 0 ]; then
  echo "Installing NVIDIA GPU Operator and DRA driver"
  privileged_ns gpu-operator
  helm_component gpu-operator 15m --wait
  privileged_ns nvidia-dra-driver-gpu
  helm_component nvidia-dra-driver 15m --wait
fi

echo "Bootstrap complete."
