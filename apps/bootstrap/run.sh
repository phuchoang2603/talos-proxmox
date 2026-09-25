#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
: "${ENV_NAME:?ENV_NAME is required}"

if [ "${ENV_NAME}" = argocd ]; then
  "${APPS_ROOT}/bootstrap/bootstrap.sh"
  exec "${APPS_ROOT}/bootstrap/bootstrap-argocd.sh"
fi

secrets=(CLOUDFLARE_TUNNEL_TOKEN)
longhorn_nodes="$(jq '[.[] | select(.role == "longhorn")] | length' "${APPS_ROOT}/../terraform/cluster/env/${ENV_NAME}/k8s_nodes.json")"
if (( longhorn_nodes > 0 )); then
  secrets+=(LONGHORN_AWS_ENDPOINTS LONGHORN_AWS_ACCESS_KEY_ID LONGHORN_AWS_SECRET_ACCESS_KEY)
fi
if [[ "${ENV_NAME}" == dev || "${ENV_NAME}" == prod ]]; then
  secrets+=(AUTOSCALER_AWS_ACCESS_KEY_ID AUTOSCALER_AWS_SECRET_ACCESS_KEY)
fi

doppler run --only-secrets "$(IFS=,; echo "${secrets[*]}")" -- "${APPS_ROOT}/bootstrap/bootstrap.sh"
