#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/charts.sh

tofu fmt -check -recursive terraform
for root in terraform/foundation terraform/cluster terraform/platform; do
  tofu -chdir="$root" init -backend=false -input=false -lockfile=readonly >/dev/null
  tofu -chdir="$root" validate
done

helm_lint() {
  local chart=$1
  shift 2
  helm lint --quiet --kube-version "$kube_version" "$chart" "$@"
}
each_chart helm_lint

rendered=$(mktemp -d)
trap 'rm -rf "$rendered"' EXIT
scripts/render.sh "$rendered"
conftest test --policy policy "$rendered"/*.yaml
