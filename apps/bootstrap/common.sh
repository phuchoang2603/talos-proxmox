#!/usr/bin/env bash
# Shared bootstrap helpers. Source from a script with set -euo pipefail.
APPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPONENTS="${APPS_ROOT}/components"

# component, timeout, additional Helm flags.
# Callers pass --wait where appropriate; Cilium's first pass must not wait for SPIRE.
helm_component() {
  local component="$1" timeout="$2"
  shift 2
  local dir="${COMPONENTS}/${component}" release namespace
  release="$(jq -er .releaseName "${dir}/release.json")"
  namespace="$(jq -er .namespace "${dir}/release.json")"
  local values=(--values "${dir}/values.yaml")
  if [ -f "${dir}/environments/${ENV_NAME}/values.yaml" ]; then
    values+=(--values "${dir}/environments/${ENV_NAME}/values.yaml")
  fi
  helm upgrade --install --timeout "${timeout}" \
    --namespace "${namespace}" \
    "${values[@]}" "$@" "${release}" "${dir}"
}

privileged_ns() {
  kubectl apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: $1
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
YAML
}
