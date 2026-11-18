---
name: verify
description: Prove a change in talos-proxmox is correct with repo:lint, a chart render diff, the Provision plan and Argo CD health.
---

Run everything inside devenv. This repo has no tests.

1. Static checks: `devenv tasks run repo:lint`. It runs the shared ast-grep rules, `tofu fmt`/`validate`, `helm lint`, and the conftest policies in `policy/` over every rendered chart.
2. Render diff: `devenv shell -- scripts/render-diff.sh [base-ref]` renders every chart against the merge base (default `origin/main`) and HEAD. Confirm the diff contains only the intended changes.
3. After pushing, read the Provision plan: `gh run list --workflow Provision --limit 3`, then `gh run view <id> --log` and check the plan of each root. A change that touches no OpenTofu root or bootstrap chart must plan no changes.
4. Cluster state: use the `talos-k8s` skill to get access, then check that the root Application and its children are Synced and Healthy in Argo CD.
