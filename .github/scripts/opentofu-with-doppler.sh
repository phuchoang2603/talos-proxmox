#!/usr/bin/env bash
set -euo pipefail

export TF_VAR_proxmox_endpoint="$PROXMOX_ENDPOINT"
export TF_VAR_proxmox_username="$PROXMOX_USERNAME"
export TF_VAR_proxmox_password="$PROXMOX_PASSWORD"

if [[ "${TF_VAR_env:-}" != argocd ]]; then
  : "${AWS_PROVIDER_ACCESS_KEY_ID:?AWS provider key required for dev/prod}"
  : "${AWS_PROVIDER_SECRET_ACCESS_KEY:?AWS provider secret required for dev/prod}"
  export TF_VAR_aws_provider_access_key_id="$AWS_PROVIDER_ACCESS_KEY_ID"
  export TF_VAR_aws_provider_secret_access_key="$AWS_PROVIDER_SECRET_ACCESS_KEY"
fi

exec tofu "$@"
