#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

KUBE_VERSION="${KUBE_VERSION:-1.36.3}"

for chart in "${APPS_ROOT}/argocd/platform" "${COMPONENTS}"/*; do
  [ -f "${chart}/Chart.yaml" ] || continue
  helm lint "${chart}" --kube-version "${KUBE_VERSION}"
  for overlay in "${chart}"/environments/*/values.yaml; do
    [ -f "${overlay}" ] || continue
    helm lint "${chart}" --kube-version "${KUBE_VERSION}" --values "${overlay}"
  done
done

helm lint "${APPS_ROOT}/argocd/platform" --kube-version "${KUBE_VERSION}" --set cluster=prod
