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
: "${VAULT_ADDR:?VAULT_ADDR is required}"

export ENV_NAME IP_LB_RANGE IP_INGRESS SSL_DOMAIN SSL_API_TOKEN SSL_EMAIL VAULT_ADDR
export SSL_LOCAL_DOMAIN="${ENV_NAME}.${SSL_DOMAIN}"
export KUBE_VIP_VERSION="${KUBE_VIP_VERSION:-v0.8.0}"
export KUBE_VIP_INTERFACE="${KUBE_VIP_INTERFACE:-eth0}"

render() {
  local src="$1"
  local dest="${RENDER}/$(basename "${src%.tmpl}")"
  envsubst <"${src}" >"${dest}"
  echo "${dest}"
}

echo "Waiting for Kubernetes API..."
until kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

kubectl wait --for=condition=Ready nodes --all --timeout=15m

helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo add longhorn https://charts.longhorn.io --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update

echo "Applying kube-vip (LoadBalancer services only; API VIP is Talos)"
kubectl apply -f "${ROOT}/manifests/kube-vip-rbac.yaml"
kubectl apply -f "$(render "${ROOT}/manifests/kube-vip-ds.yaml.tmpl")"
kubectl apply -f "$(render "${ROOT}/manifests/kube-vip-cloud-controller.yaml.tmpl")"

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

echo "Installing Traefik"
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version v39.0.7 \
  --values "$(render "${ROOT}/values/traefik.yaml.tmpl")" \
  --wait --timeout 10m

kubectl apply -f "$(render "${ROOT}/manifests/traefik-wildcard-cert.yaml.tmpl")"

echo "Installing External Secrets"
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version v2.2.0 \
  --set installCRDs=true \
  --wait --timeout 10m

kubectl apply -f "${ROOT}/manifests/external-secrets-rbac.yaml"
kubectl apply -f "$(render "${ROOT}/manifests/external-secrets-cluster-store.yaml.tmpl")"

echo "Installing Longhorn"
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version v1.11.1 \
  --values "${ROOT}/values/longhorn.yaml" \
  --wait --timeout 15m

kubectl apply -f "${ROOT}/manifests/longhorn-storage-class.yaml"
kubectl apply -f "${ROOT}/manifests/longhorn-recurringjob.yaml"
kubectl apply -f "${ROOT}/manifests/longhorn-minio-cred.yaml"
kubectl apply -f "$(render "${ROOT}/manifests/longhorn-ingress.yaml.tmpl")"

echo "Installing Argo CD"
helm upgrade --install argo-cd argo/argo-cd \
  --namespace argo-cd \
  --create-namespace \
  --version v9.4.17 \
  --values "${ROOT}/values/argo-cd.yaml" \
  --wait --timeout 15m

kubectl apply -f "$(render "${ROOT}/manifests/argo-ingress.yaml.tmpl")"

echo "Bootstrap complete."
