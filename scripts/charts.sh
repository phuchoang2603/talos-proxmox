kube_version=1.37.2

each_chart() {
  local callback=$1 chart overlay cluster overlays
  for chart in apps/components/*/; do
    [ -f "${chart}Chart.yaml" ] || continue
    overlays=("${chart}"environments/*/values.yaml)
    if [ ! -f "${overlays[0]}" ]; then
      "$callback" "$chart" "components-$(basename "$chart")"
      continue
    fi
    for overlay in "${overlays[@]}"; do
      "$callback" "$chart" "components-$(basename "$chart")-$(basename "$(dirname "$overlay")")" --values "$overlay"
    done
  done
  for chart in apps/argocd/*/; do
    for cluster in dev prod; do
      "$callback" "$chart" "argocd-$(basename "$chart")-$cluster" --set cluster="$cluster"
    done
  done
}
