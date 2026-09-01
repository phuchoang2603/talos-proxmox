#!/usr/bin/env bash
set -euo pipefail

# GPU-only bootstrap: Argo CD (multi-cluster UI), External Secrets Operator, Doppler stores.
# Run after apps/bootstrap.sh with ENV_NAME=gpu.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS="${ROOT}/manifests"
VALUES="${ROOT}/values"
TF_ENV="${ROOT}/../terraform-provision/env"

: "${ENV_NAME:?ENV_NAME is required}"
: "${KUBECONFIG:?KUBECONFIG is required}"
: "${DOPPLER_READ_TOKEN:?DOPPLER_READ_TOKEN is required}"

if [ "${ENV_NAME}" != gpu ]; then
  echo "bootstrap-gpu.sh is only for ENV_NAME=gpu (got ${ENV_NAME})" >&2
  exit 1
fi

ARGO_CD_VERSION="${ARGO_CD_VERSION:-v9.4.17}"
EXTERNAL_SECRETS_VERSION="${EXTERNAL_SECRETS_VERSION:-0.13.0}"
DOPPLER_PROJECT="${DOPPLER_PROJECT:-talos-proxmox}"

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

argo_cluster_config() {
  local kubeconfig="$1"
  local ca cert key token
  ca="$(kubectl --kubeconfig="${kubeconfig}" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
  cert="$(kubectl --kubeconfig="${kubeconfig}" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')"
  key="$(kubectl --kubeconfig="${kubeconfig}" config view --raw -o jsonpath='{.users[0].user.client-key-data}')"
  token="$(kubectl --kubeconfig="${kubeconfig}" config view --raw -o jsonpath='{.users[0].user.token}')"
  if [ -n "${token}" ]; then
    jq -n --arg token "${token}" --arg ca "${ca}" \
      '{bearerToken: $token, tlsClientConfig: {caData: $ca, insecure: false}}'
  elif [ -n "${cert}" ] && [ -n "${key}" ]; then
    jq -n --arg cert "${cert}" --arg key "${key}" --arg ca "${ca}" \
      '{tlsClientConfig: {caData: $ca, certData: $cert, keyData: $key, insecure: false}}'
  else
    echo "kubeconfig has no bearer token or client cert credentials" >&2
    return 1
  fi
}

register_argo_cluster() {
  local name="$1" server="$2" kubeconfig="$3"
  local config
  config="$(argo_cluster_config "${kubeconfig}")"
  kubectl create secret generic "cluster-${name}" \
    --namespace argo-cd \
    --from-literal=name="${name}" \
    --from-literal=server="${server}" \
    --from-literal=config="${config}" \
    --dry-run=client -o yaml | \
    kubectl label --local -f - argocd.argoproj.io/secret-type=cluster -o yaml | \
    kubectl apply -f -
  echo "Registered Argo CD cluster ${name} -> ${server}"
}

fetch_kubeconfig() {
  local config="$1" dest="$2"
  DOPPLER_TOKEN="${DOPPLER_READ_TOKEN}" doppler secrets get KUBECONFIG \
    --project "${DOPPLER_PROJECT}" --config "${config}" --plain > "${dest}"
}

echo "Installing External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm_up external-secrets external-secrets/external-secrets external-secrets "${EXTERNAL_SECRETS_VERSION}" "${VALUES}/external-secrets.yaml" --create-namespace
kubectl wait --for=condition=Established --timeout=5m \
  crd/clustersecretstores.external-secrets.io \
  crd/externalsecrets.external-secrets.io

kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic doppler-token \
  --namespace external-secrets \
  --from-literal=dopplerToken="${DOPPLER_READ_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${MANIFESTS}/gpu/doppler.yaml"

echo "Installing Argo CD"
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm_up argo-cd argo/argo-cd argo-cd "${ARGO_CD_VERSION}" "${VALUES}/argo-cd.yaml" 20m --create-namespace
kubectl apply -f "${MANIFESTS}/env/gpu/argo-ingress.yaml"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for remote in dev prod; do
  kc="${tmpdir}/${remote}-kubeconfig"
  server="https://$(jq -r .vip "${TF_ENV}/${remote}/network.json"):6443"
  fetch_kubeconfig "${remote}" "${kc}"
  register_argo_cluster "${remote}" "${server}" "${kc}"
done

echo "GPU bootstrap complete."
