#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER="${ROOT}/.rendered"
mkdir -p "${RENDER}"

: "${KUBECONFIG:?KUBECONFIG is required}"
: "${ENV_NAME:?ENV_NAME is required}"
: "${IP_LB_RANGE:?IP_LB_RANGE is required}"
: "${IP_INGRESS:?IP_INGRESS is required}"
: "${SSL_DOMAIN:?SSL_DOMAIN is required}"
: "${SSL_API_TOKEN:?SSL_API_TOKEN is required}"
: "${SSL_EMAIL:?SSL_EMAIL is required}"
: "${LONGHORN_AWS_ENDPOINTS:?LONGHORN_AWS_ENDPOINTS is required}"
: "${LONGHORN_AWS_ACCESS_KEY_ID:?LONGHORN_AWS_ACCESS_KEY_ID is required}"
: "${LONGHORN_AWS_SECRET_ACCESS_KEY:?LONGHORN_AWS_SECRET_ACCESS_KEY is required}"

export ENV_NAME IP_LB_RANGE IP_INGRESS SSL_DOMAIN SSL_API_TOKEN SSL_EMAIL
export SSL_LOCAL_DOMAIN="${ENV_NAME}.${SSL_DOMAIN}"
export CILIUM_VERSION="${CILIUM_VERSION:-1.18.13}"
export CILIUM_INTERFACE="${CILIUM_INTERFACE:-eth0}"
export GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.3.0}"
export IP_LB_START="${IP_LB_RANGE%%-*}"
export IP_LB_STOP="${IP_LB_RANGE##*-}"

render() {
  local src="$1"
  local dest="${RENDER}/$(basename "${src%.tmpl}")"
  envsubst <"${src}" >"${dest}"
  echo "${dest}"
}

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
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add longhorn https://charts.longhorn.io --force-update
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
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
  --values "$(render "${ROOT}/values/cilium.yaml.tmpl")" \
  --wait --timeout 15m

kubectl wait --for=condition=Established crd/ciliumloadbalancerippools.cilium.io --timeout=5m
kubectl wait --for=condition=Established crd/ciliuml2announcementpolicies.cilium.io --timeout=5m
kubectl apply -f "$(render "${ROOT}/manifests/cilium-l2.yaml.tmpl")"

echo "Waiting for nodes to become Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=15m

echo "Installing cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.1 \
  --set crds.enabled=true \
  --set extraArgs[0]="--dns01-recursive-nameservers-only" \
  --set extraArgs[1]="--dns01-recursive-nameservers=1.1.1.1:53" \
  --wait --timeout 10m

echo "Applying cert-manager issuer"
kubectl apply -f "$(render "${ROOT}/manifests/cert-manager-issuer.yaml.tmpl")"

echo "Applying Cilium Gateway"
kubectl apply -f "$(render "${ROOT}/manifests/cilium-gateway.yaml.tmpl")"
kubectl wait --for=condition=Ready certificate/wildcard-cert -n cilium-ingress --timeout=10m
kubectl apply -f "$(render "${ROOT}/manifests/hubble-ingress.yaml.tmpl")"

echo "Installing Longhorn"
kubectl apply -f "${ROOT}/manifests/longhorn-namespace.yaml"
kubectl create secret generic longhorn-minio-credentials \
  --namespace longhorn-system \
  --from-literal=AWS_ENDPOINTS="${LONGHORN_AWS_ENDPOINTS}" \
  --from-literal=AWS_ACCESS_KEY_ID="${LONGHORN_AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${LONGHORN_AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --version v1.11.1 \
  --values "${ROOT}/values/longhorn.yaml" \
  --wait --timeout 15m

kubectl apply -f "${ROOT}/manifests/longhorn-storage-class.yaml"
kubectl apply -f "${ROOT}/manifests/longhorn-recurringjob.yaml"
kubectl apply -f "$(render "${ROOT}/manifests/longhorn-ingress.yaml.tmpl")"

if [ "$(jq 'length' "${ROOT}/../terraform-provision/env/${ENV_NAME}/gpu_nodes.json")" -gt 0 ]; then
  echo "Installing NVIDIA GPU Operator"
  kubectl apply -f "${ROOT}/manifests/gpu-operator-namespace.yaml"
  helm upgrade --install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator \
    --version v26.7.0 \
    --values "${ROOT}/values/gpu-operator.yaml" \
    --wait --timeout 15m
fi

echo "Installing Argo CD"
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argo-cd \
  --create-namespace \
  --version v9.4.17 \
  --values "${ROOT}/values/argo-cd.yaml" \
  --wait --timeout 15m

kubectl apply -f "$(render "${ROOT}/manifests/argo-ingress.yaml.tmpl")"

echo "Bootstrap complete."
