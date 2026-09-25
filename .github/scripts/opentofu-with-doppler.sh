#!/usr/bin/env bash
set -euo pipefail

export TF_VAR_proxmox_endpoint="$PROXMOX_ENDPOINT"
export TF_VAR_proxmox_username="$PROXMOX_USERNAME"
export TF_VAR_proxmox_password="$PROXMOX_PASSWORD"

if [[ "${TF_VAR_env:-}" != argocd ]]; then
  : "${TF_VAR_aws_provider_access_key_id:?AWS provider key required for dev/prod}"
  : "${TF_VAR_aws_provider_secret_access_key:?AWS provider secret required for dev/prod}"
fi

unset AWS_SESSION_TOKEN
exec tofu "$@"
