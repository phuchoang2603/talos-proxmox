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

echo "Installing Argo CD"
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argo-cd \
  --create-namespace \
  --version v9.4.17 \
  --values "${ROOT}/values/argo-cd.yaml" \
  --wait --timeout 15m

kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=2m

echo "Writing Longhorn backup secret"
kubectl apply -f "${ROOT}/manifests/longhorn-namespace.yaml"
kubectl create secret generic longhorn-minio-credentials \
  --namespace longhorn-system \
  --from-literal=AWS_ENDPOINTS="${LONGHORN_AWS_ENDPOINTS}" \
  --from-literal=AWS_ACCESS_KEY_ID="${LONGHORN_AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${LONGHORN_AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Registering Argo CD applications"
kubectl apply -f "${ROOT}/argocd/${ENV_NAME}"

echo "Bootstrap complete. Argo CD syncs Longhorn, GPU Operator, and Gateway routes from git."
