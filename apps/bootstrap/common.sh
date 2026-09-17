#!/usr/bin/env bash
# Shared bootstrap helpers. Source from a script with set -euo pipefail.
APPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPONENTS="${APPS_ROOT}/components"

component_version() {
  local config="${COMPONENTS}/$1/release.json" version override
  version="$(jq -er .version "${config}")"
  override="$(jq -r '.versionEnv // empty' "${config}")"
  if [ -n "${override}" ]; then
    version="${!override:-${version}}"
  fi
  printf '%s\n' "${version}"
}

# component, release name, namespace, timeout, additional Helm flags.
# Callers pass --wait where appropriate; Cilium's first pass must not wait for SPIRE.
helm_component() {
  local component="$1" release="$2" namespace="$3" timeout="$4"
  shift 4
  local dir="${COMPONENTS}/${component}" chart
  chart="${dir}/$(jq -er .chartPath "${dir}/release.json")"
  if [ ! -f "${chart}" ]; then
    echo "Missing packaged chart: ${chart}" >&2
    return 1
  fi
  local values=(--values "${dir}/values.yaml")
  if [ -f "${dir}/environments/${ENV_NAME}/values.yaml" ]; then
    values+=(--values "${dir}/environments/${ENV_NAME}/values.yaml")
  fi
  helm upgrade --install --timeout "${timeout}" \
    --namespace "${namespace}" \
    "${values[@]}" "$@" "${release}" "${chart}"
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
