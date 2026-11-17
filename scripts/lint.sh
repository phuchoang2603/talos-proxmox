#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

kube_version=1.37.2

helm_lint() {
  helm lint --quiet --kube-version "$kube_version" "$@"
}

tofu fmt -check -recursive terraform
for root in terraform/foundation terraform/cluster terraform/platform; do
  tofu -chdir="$root" init -backend=false -input=false -lockfile=readonly >/dev/null
  tofu -chdir="$root" validate
done

for chart in apps/components/*/; do
  [ -f "${chart}Chart.yaml" ] || continue
  helm_lint "$chart"
  for overlay in "${chart}"environments/*/values.yaml; do
    [ -f "$overlay" ] || continue
    helm_lint "$chart" --values "$overlay"
  done
done

for chart in apps/argocd/*/; do
  for cluster in dev prod; do
    helm_lint "$chart" --set cluster="$cluster"
  done
done
