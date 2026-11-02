#!/usr/bin/env bash
# Smoke-test self-hosted HYUI preflight across all available compiler stages.
# Usage: tests/ui/test-stage-ui-preflight.sh [repo-root]
set -euo pipefail
root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$root"
doc="samples/ui_studio/Studio.hyui"
project="samples/ui_studio/Studio.hyproj"
stages=(
  "build/self_hosting/linux/hydrogen-stage1"
  "build/self_hosting/linux/hydrogen-stage2"
  "build/self_hosting/linux/hydrogen-stage3"
)
for compiler in "${stages[@]}"; do
  if [[ ! -x "$compiler" ]]; then
    echo "Missing compiler: $compiler" >&2
    exit 1
  fi
  "$compiler" ui validate "$doc"
  "$compiler" ui validate "$project"
  if "$compiler" ui validate "$doc.does-not-exist.hyui"; then
    echo "Missing HYUI document incorrectly passed validation: $compiler" >&2
    exit 1
  fi
done
echo "All three Hydrogen compiler stages validated HYUI documents."
