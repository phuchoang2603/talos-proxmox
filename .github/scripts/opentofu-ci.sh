#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}/terraform/cluster"

: "${ENV_NAME:?ENV_NAME is required}"
: "${DOPPLER_TOKEN:?DOPPLER_TOKEN is required}"
if [ "${GITHUB_REF:-}" != refs/heads/main ] || [[ "${GITHUB_EVENT_NAME:-}" != push && "${GITHUB_EVENT_NAME:-}" != workflow_dispatch ]]; then
  echo 'OpenTofu applies require a push or dispatch on main.' >&2
  exit 1
fi

secrets=AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,PROXMOX_ENDPOINT,PROXMOX_USERNAME,PROXMOX_PASSWORD
if [ "${ENV_NAME}" != argocd ]; then
  : "${AWS_ACCESS_KEY_ID:?OIDC credentials required for dev/prod}"
  : "${AWS_SECRET_ACCESS_KEY:?OIDC credentials required for dev/prod}"
  : "${AWS_SESSION_TOKEN:?OIDC session token required for dev/prod}"
  export TF_VAR_aws_provider_access_key_id="$AWS_ACCESS_KEY_ID"
  export TF_VAR_aws_provider_secret_access_key="$AWS_SECRET_ACCESS_KEY"
  export TF_VAR_aws_provider_session_token="$AWS_SESSION_TOKEN"
fi

tf() {
  doppler run --only-secrets "${secrets}" -- \
    bash "${repo_root}/.github/scripts/opentofu-with-doppler.sh" "$@"
}

tf init -input=false -backend-config="key=talos-${ENV_NAME}.tfstate"
plan_flags=()
if [ "${ACTION:-apply}" = destroy ]; then
  plan_flags+=(-destroy)
fi
tf plan -input=false -no-color "${plan_flags[@]}" -var-file="env/${ENV_NAME}/main.tfvars" -out .planfile

tf apply -auto-approve .planfile
if [ "${ACTION:-apply}" = destroy ]; then
  exit 0
fi

tf output -raw kubeconfig | doppler secrets set --silent --type yaml KUBECONFIG
tf output -raw talosconfig | doppler secrets set --silent --type yaml TALOSCONFIG
tf output -raw kubeconfig > "${GITHUB_WORKSPACE:-${repo_root}}/kubeconfig"
chmod 600 "${GITHUB_WORKSPACE:-${repo_root}}/kubeconfig"
