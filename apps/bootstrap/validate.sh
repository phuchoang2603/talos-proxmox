#!/usr/bin/env bash
# Offline validation: no cluster access or chart downloads.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Match the Kubernetes version configured in the Terraform environment files.
KUBE_VERSION="${KUBE_VERSION:-1.36.3}"

for script in "${APPS_ROOT}"/bootstrap/*.sh; do
  bash -n "${script}"
done
jq -e '.version | type == "string"' "${COMPONENTS}/gateway-api/release.json" >/dev/null

for cluster in dev prod; do
  helm lint "${APPS_ROOT}/argocd/platform" --strict --set "cluster=${cluster}"
  helm template "platform-${cluster}" "${APPS_ROOT}/argocd/platform" \
    --namespace argo-cd --set "cluster=${cluster}" >/dev/null
done

for chart in "${COMPONENTS}"/*/Chart.yaml; do
  chart="$(dirname "${chart}")"
  namespace=operators
  release="$(basename "${chart}")"
  if [ -f "${chart}/release.json" ]; then
    namespace="$(jq -er .namespace "${chart}/release.json")"
    release="$(jq -er .releaseName "${chart}/release.json")"
  elif [ "${release}" = observability ]; then
    namespace=monitoring
  fi
  helm lint "${chart}" --namespace "${namespace}" --kube-version "${KUBE_VERSION}"
  helm template "${release}" "${chart}" --kube-version "${KUBE_VERSION}" \
    --namespace "${namespace}" --include-crds >/dev/null
  for overlay in "${chart}"/environments/*/values.yaml; do
    [ -f "${overlay}" ] || continue
    helm lint "${chart}" --namespace "${namespace}" --kube-version "${KUBE_VERSION}" --values "${overlay}"
    helm template "${release}" "${chart}" --kube-version "${KUBE_VERSION}" \
      --namespace "${namespace}" --values "${overlay}" --include-crds >/dev/null
  done
done
