# Local Path Provisioner

`charts/local-path-provisioner-0.0.30.tgz` packages the official Rancher Helm chart
from tag `v0.0.30`, commit `c4fdcada94c2e632cd7d9231e73406d554eb40e2`.
It includes the upstream Apache-2.0 license. The unpacked source is not stored
in this repository. Local settings live in `values.yaml`.

To reproduce the package from the repository root:

```bash
chart_tmp=$(mktemp -d)
curl -fsSL https://codeload.github.com/rancher/local-path-provisioner/tar.gz/c4fdcada94c2e632cd7d9231e73406d554eb40e2 \
  -o "$chart_tmp/source.tar.gz"
tar -xzf "$chart_tmp/source.tar.gz" -C "$chart_tmp" --strip-components=1
cp "$chart_tmp/LICENSE" "$chart_tmp/deploy/chart/local-path-provisioner/LICENSE"
helm package "$chart_tmp/deploy/chart/local-path-provisioner" \
  --destination apps/components/local-path-provisioner/charts
rm -rf "$chart_tmp"
```

For an upgrade, choose a pinned upstream revision, update `release.json` and these
source details, and run `apps/bootstrap/validate.sh`.
