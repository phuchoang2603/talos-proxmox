#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

base=$(git merge-base HEAD "${1:-origin/main}")
[ "$base" != "$(git rev-parse HEAD)" ] || base=$(git rev-parse HEAD~1)

work=$(mktemp -d)
trap 'git worktree remove --force "$work/base"; rm -rf "$work"' EXIT
git worktree add --detach --quiet "$work/base" "$base"

scripts/render.sh "$work/head"
scripts/render.sh "$work/before" "$work/base"
diff -ru "$work/before" "$work/head" | sed "s|$work/||g" || true
