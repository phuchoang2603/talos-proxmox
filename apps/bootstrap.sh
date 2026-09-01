#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${ROOT}/manifests"
VALUES="${ROOT}/values"

: "${KUBECONFIG:?KUBECONFIG is required}"

INV="${ROOT}/../terraform-provision/env/${ENV_NAME:?ENV_NAME is required}"
LONGHORN_NODES="$(jq 'length' "${INV}/longhorn_nodes.json")"
if [ "${LONGHORN_NODES}" -gt 0 ]; then
  : "${LONGHORN_AWS_ENDPOINTS:?LONGHORN_AWS_ENDPOINTS is required}"
  : "${LONGHORN_AWS_ACCESS_KEY_ID:?LONGHORN_AWS_ACCESS_KEY_ID is required}"
  : "${LONGHORN_AWS_SECRET_ACCESS_KEY:?LONGHORN_AWS_SECRET_ACCESS_KEY is required}"
fi

CILIUM_VERSION="${CILIUM_VERSION:-1.18.13}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.3.0}"
LONGHORN_VERSION="${LONGHORN_VERSION:-1.11.1}"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-3.14.0}"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v26.7.0}"
NVIDIA_DRA_VERSION="${NVIDIA_DRA_VERSION:-25.12.0}"

helm_up() {
  local name="$1" chart="$2" ns="$3" version="$4" values="$5"
  shift 5
  local timeout=15m
  if [[ "${1:-}" == [0-9]*m ]]; then
    timeout="$1"
    shift
  fi
  helm upgrade --install --wait --timeout "${timeout}" \
    --namespace "${ns}" --version "${version}" --values "${values}" \
    "$@" "${name}" "${chart}"
}

privileged_ns() {
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $1
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOF
}

echo "Waiting for Kubernetes API..."
until kubectl get --raw=/readyz >/dev/null 2>&1; do
  sleep 5
done

expected_nodes=0
for inventory in k8s_nodes.json longhorn_nodes.json gpu_nodes.json; do
  expected_nodes=$((expected_nodes + $(jq 'length' "${INV}/${inventory}")))
done
echo "Waiting for ${expected_nodes} nodes to register..."
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c . || true)" -ge "${expected_nodes}" ]; do
  sleep 5
done

helm repo add cilium https://helm.cilium.io/ --force-update
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
if [ "${LONGHORN_NODES}" -gt 0 ]; then
  helm repo add longhorn https://charts.longhorn.io --force-update
fi

echo "Installing Gateway API CRDs ${GATEWAY_API_VERSION}"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established --timeout=2m \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io

echo "Installing Cilium"
helm_up cilium cilium/cilium kube-system "${CILIUM_VERSION}" "${VALUES}/cilium.yaml"
kubectl wait --for=condition=Established --timeout=5m \
  crd/ciliumloadbalancerippools.cilium.io \
  crd/ciliuml2announcementpolicies.cilium.io
kubectl apply -f "${MANIFESTS}/env/${ENV_NAME}/network.yaml"

echo "Waiting for nodes to become Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=15m

echo "Installing metrics-server"
helm_up metrics-server metrics-server/metrics-server kube-system "${METRICS_SERVER_VERSION}" "${VALUES}/metrics-server.yaml" 5m

if [ "${LONGHORN_NODES}" -gt 0 ]; then
  echo "Installing Longhorn"
  privileged_ns longhorn-system
  kubectl create secret generic longhorn-minio-credentials \
    --namespace longhorn-system \
    --from-literal=AWS_ENDPOINTS="${LONGHORN_AWS_ENDPOINTS}" \
    --from-literal=AWS_ACCESS_KEY_ID="${LONGHORN_AWS_ACCESS_KEY_ID}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${LONGHORN_AWS_SECRET_ACCESS_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
  helm_up longhorn longhorn/longhorn longhorn-system "${LONGHORN_VERSION}" "${VALUES}/longhorn.yaml"
  kubectl apply -f "${MANIFESTS}/longhorn.yaml"
  kubectl apply -f "${MANIFESTS}/env/${ENV_NAME}/longhorn-ingress.yaml"
fi

if [ "$(jq 'length' "${INV}/gpu_nodes.json")" -gt 0 ]; then
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
  echo "Installing NVIDIA GPU Operator and DRA driver"
  privileged_ns gpu-operator
  helm_up gpu-operator nvidia/gpu-operator gpu-operator "${GPU_OPERATOR_VERSION}" "${VALUES}/gpu-operator.yaml"
  privileged_ns nvidia-dra-driver-gpu
  helm_up nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu nvidia-dra-driver-gpu "${NVIDIA_DRA_VERSION}" "${VALUES}/nvidia-dra-driver.yaml"
fi

echo "Bootstrap complete."
