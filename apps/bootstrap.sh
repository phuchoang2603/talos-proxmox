#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${ENV_NAME:?ENV_NAME is required}"
: "${LONGHORN_AWS_ENDPOINTS:?LONGHORN_AWS_ENDPOINTS is required}"
: "${LONGHORN_AWS_ACCESS_KEY_ID:?LONGHORN_AWS_ACCESS_KEY_ID is required}"
: "${LONGHORN_AWS_SECRET_ACCESS_KEY:?LONGHORN_AWS_SECRET_ACCESS_KEY is required}"

CILIUM_VERSION="${CILIUM_VERSION:-1.18.13}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.3.0}"
LONGHORN_VERSION="${LONGHORN_VERSION:-1.11.1}"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-3.14.0}"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v26.7.0}"
ARGO_CD_VERSION="${ARGO_CD_VERSION:-v9.4.17}"

echo "Waiting for Kubernetes API..."
until kubectl get --raw=/readyz >/dev/null 2>&1; do
  sleep 5
done

expected_nodes=$(($(jq 'length' "${ROOT}/../terraform-provision/env/${ENV_NAME}/k8s_nodes.json") + $(jq 'length' "${ROOT}/../terraform-provision/env/${ENV_NAME}/longhorn_nodes.json") + $(jq 'length' "${ROOT}/../terraform-provision/env/${ENV_NAME}/gpu_nodes.json")))
echo "Waiting for ${expected_nodes} nodes to register..."
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c . || true)" -ge "${expected_nodes}" ]; do
  sleep 5
done

helm repo add cilium https://helm.cilium.io/ --force-update
helm repo add longhorn https://charts.longhorn.io --force-update
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update

echo "Installing Gateway API CRDs ${GATEWAY_API_VERSION}"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io --timeout=2m
kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io --timeout=2m
kubectl wait --for=condition=Established crd/httproutes.gateway.networking.k8s.io --timeout=2m

echo "Installing Cilium (CNI, kube-proxy replacement, L2 LoadBalancer, Gateway API)"
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version "${CILIUM_VERSION}" \
  --values "${ROOT}/values/cilium.yaml" \
  --wait --timeout 15m

kubectl wait --for=condition=Established crd/ciliumloadbalancerippools.cilium.io --timeout=5m
kubectl wait --for=condition=Established crd/ciliuml2announcementpolicies.cilium.io --timeout=5m
kubectl apply -f "${ROOT}/manifests/env/${ENV_NAME}/cilium-l2.yaml"

echo "Waiting for nodes to become Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=15m

echo "Installing metrics-server"
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --version "${METRICS_SERVER_VERSION}" \
  --values "${ROOT}/values/metrics-server.yaml" \
  --wait --timeout 5m

echo "Writing Longhorn backup secret"
kubectl apply -f "${ROOT}/manifests/longhorn-namespace.yaml"
kubectl create secret generic longhorn-minio-credentials \
  --namespace longhorn-system \
  --from-literal=AWS_ENDPOINTS="${LONGHORN_AWS_ENDPOINTS}" \
  --from-literal=AWS_ACCESS_KEY_ID="${LONGHORN_AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${LONGHORN_AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Longhorn"
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version "${LONGHORN_VERSION}" \
  --values "${ROOT}/values/longhorn.yaml" \
  --wait --timeout 15m

kubectl apply -f "${ROOT}/manifests/longhorn-storage-class.yaml"
kubectl apply -f "${ROOT}/manifests/longhorn-recurringjob.yaml"

gpu_count="$(jq 'length' "${ROOT}/../terraform-provision/env/${ENV_NAME}/gpu_nodes.json")"
if [ "${gpu_count}" -gt 0 ]; then
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
  echo "Installing NVIDIA GPU Operator"
  kubectl apply -f "${ROOT}/manifests/gpu-operator-namespace.yaml"
  helm upgrade --install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator \
    --version "${GPU_OPERATOR_VERSION}" \
    --values "${ROOT}/values/gpu-operator.yaml" \
    --wait --timeout 15m
fi

echo "Installing Argo CD"
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argo-cd \
  --create-namespace \
  --version "${ARGO_CD_VERSION}" \
  --values "${ROOT}/values/argo-cd.yaml" \
  --wait --timeout 15m

echo "Applying Gateway routes"
kubectl apply -f "${ROOT}/manifests/env/${ENV_NAME}/gateways.yaml"
kubectl apply -f "${ROOT}/manifests/httproutes.yaml"

echo "Bootstrap complete."
