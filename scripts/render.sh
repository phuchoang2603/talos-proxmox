#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/charts.sh"

out=$(realpath -m "${1:?usage: render.sh <output-dir> [repo-root]}")
cd "${2:-$(dirname "${BASH_SOURCE[0]}")/..}"
mkdir -p "$out"

render() {
  local chart=$1 name=$2
  shift 2
  helm template "$name" "$chart" --skip-tests --namespace render --kube-version "$kube_version" "$@" >"$out/$name.yaml"
}

each_chart render
