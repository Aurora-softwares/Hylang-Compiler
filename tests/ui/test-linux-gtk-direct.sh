#!/usr/bin/env bash
# End-to-end native GTK4 frontend build. No hyui-native or Qt is needed.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$root"
# Existing CI passes no arguments and tests Stage 1. Developers can run
# --all-stages to check native GTK4 generation by Stages 1, 2 and 3.
if [[ "${1:-}" == "--all-stages" ]]; then
  compilers=(
    "build/self_hosting/linux/hydrogen-stage1"
    "build/self_hosting/linux/hydrogen-stage2"
    "build/self_hosting/linux/hydrogen-stage3"
  )
elif [[ $# -gt 0 ]]; then
  compilers=("$1")
else
  compilers=("build/self_hosting/linux/hydrogen-stage1")
fi
for compiler in "${compilers[@]}"; do
  [[ -x "$compiler" ]] || { echo "Missing Hydrogen compiler: $compiler" >&2; exit 1; }
done
command -v pkg-config >/dev/null
pkg-config --exists gtk4 || { echo "GTK4 development package is required" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
index=0
for compiler in "${compilers[@]}"; do
index=$((index + 1))
output="$work/Studio-stage$index"
"$compiler" build samples/ui_studio/Studio.hyproj -o "$output" \
  --hide-spinner --hide-log --hide-progress
test -x "$output"
test -x "$output.runtime/app/__hyui_backend"
test -f "$output.runtime/app/Studio.hyui"
test -f "$output.runtime/app/assets/hydrogen.png"
test -f "$output.runtime/app/__hyui_document"
test ! -e "$output.runtime/hyui"
test ! -e "$output.runtime/hyui-native"
test ! -e "$output.runtime/hyui-launcher"
grep -q '"renderer":"gtk4-direct"' "$output.runtime/hyui-runtime.json"
file "$output" | grep -q 'ELF 64-bit'
if ldd "$output" | grep -q 'Qt6'; then
  echo "Direct GTK4 frontend unexpectedly links to Qt" >&2
  exit 1
fi
ldd "$output" | grep -q 'libgtk-4'
# gtk_application_new and the GTK event loop require a running display.
export GDK_BACKEND=x11
export GTK_A11Y=none
# GTK warnings about invalid widget types must be caught as regressions.
export G_DEBUG=fatal-criticals
"$output" --event ShowControls:showControls --state-output "$work/state.json"
python3 - "$work/state.json" <<'PY'
import json
import sys
from pathlib import Path
state=json.loads(Path(sys.argv[1]).read_text())
assert state["pages.value"] == 1, state
assert state["projectName.text"] == "Aurora Notes", state
assert "Ready when you are" in state["status.text"], state
PY
"$output" --event ShowWorkspace:showWorkspace --state-output "$work/state.json"
python3 - "$work/state.json" <<'PY'
import json
import sys
from pathlib import Path
state=json.loads(Path(sys.argv[1]).read_text())
assert state["pages.value"] == 0, state
PY
echo "Direct GTK4 application generated, launched, and dispatched Hydrogen events without hyui-native: $compiler"
done
echo "Native GTK4 direct builds passed for ${#compilers[@]} compiler stage(s)."
