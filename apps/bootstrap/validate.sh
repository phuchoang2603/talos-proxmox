#!/usr/bin/env bash
# Offline validation: no cluster access or chart downloads.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Match the Kubernetes version configured in the Terraform environment files.
KUBE_VERSION="${KUBE_VERSION:-1.36.3}"

for script in "${APPS_ROOT}"/bootstrap/*.sh; do
  bash -n "${script}"
done
for config in "${COMPONENTS}"/*/release.json; do
  jq -e '.version | type == "string"' "${config}" >/dev/null
done

for cluster in dev prod; do
  helm lint "${APPS_ROOT}/argocd/platform" --strict --set "cluster=${cluster}"
  helm template "platform-${cluster}" "${APPS_ROOT}/argocd/platform" \
    --namespace argo-cd --set "cluster=${cluster}" >/dev/null
done

for chart in "${COMPONENTS}"/*/Chart.yaml; do
  chart="$(dirname "${chart}")"
  namespace=operators
  [ "$(basename "${chart}")" != observability ] || namespace=monitoring
  helm lint "${chart}"
  helm template "$(basename "${chart}")" "${chart}" \
    --namespace "${namespace}" --include-crds >/dev/null
  for overlay in "${chart}"/environments/*/values.yaml; do
    [ -f "${overlay}" ] || continue
    helm lint "${chart}" --values "${overlay}"
    helm template "$(basename "${chart}")" "${chart}" \
      --namespace "${namespace}" --values "${overlay}" --include-crds >/dev/null
  done
done

# Bootstrap charts are installed directly from their committed packages.
for config in "${COMPONENTS}"/*/release.json; do
  chart_path="$(jq -r '.chartPath // empty' "${config}")"
  [ -n "${chart_path}" ] || continue
  dir="$(dirname "${config}")"
  chart="${dir}/${chart_path}"
  namespace="$(jq -er .namespace "${config}")"
  release="$(jq -er .releaseName "${config}")"
  test -f "${chart}"
  helm lint "${chart}" --namespace "${namespace}" --kube-version "${KUBE_VERSION}" --values "${dir}/values.yaml"
  helm template "${release}" "${chart}" --namespace "${namespace}" \
    --values "${dir}/values.yaml" --kube-version "${KUBE_VERSION}" >/dev/null
  for overlay in "${dir}"/environments/*/values.yaml; do
    [ -f "${overlay}" ] || continue
    helm lint "${chart}" --namespace "${namespace}" --kube-version "${KUBE_VERSION}" --values "${dir}/values.yaml" --values "${overlay}"
    helm template "${release}" "${chart}" --namespace "${namespace}" \
      --values "${dir}/values.yaml" --values "${overlay}" --kube-version "${KUBE_VERSION}" >/dev/null
  done
done
