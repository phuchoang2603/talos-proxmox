#!/usr/bin/env bash
set -euo pipefail

# Argo CD bootstrap: multi-cluster UI and remote cluster registration.
# Run after apps/bootstrap/bootstrap.sh with ENV_NAME=argocd.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
TF_ENV="${APPS_ROOT}/../terraform-provision/env"

: "${ENV_NAME:?ENV_NAME is required}"
: "${KUBECONFIG:?KUBECONFIG is required}"
: "${DOPPLER_READ_TOKEN:?DOPPLER_READ_TOKEN is required}"

if [ "${ENV_NAME}" != argocd ]; then
  echo "bootstrap-argocd.sh is only for ENV_NAME=argocd (got ${ENV_NAME})" >&2
  exit 1
fi

DOPPLER_PROJECT="${DOPPLER_PROJECT:-talos-proxmox}"

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

echo "Installing Argo CD"
helm_component argo-cd 20m --wait --create-namespace
kubectl apply -f "${COMPONENTS}/argo-cd/environments/argocd/ingress.yaml"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

for remote in dev prod; do
  kc="${tmpdir}/${remote}-kubeconfig"
  server="https://$(jq -r .vip "${TF_ENV}/${remote}/network.json"):6443"
  fetch_kubeconfig "${remote}" "${kc}"
  register_argo_cluster "${remote}" "${server}" "${kc}"
done

echo "Argo CD bootstrap complete."
