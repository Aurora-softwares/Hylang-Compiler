#!/usr/bin/env bash
# End-to-end native GTK4 frontend build. No hyui-native or Qt is needed.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$root"
# Existing CI passes no arguments and tests Stage 1. Developers can run
# --all-stages to check native GTK4 generation by Stages 1, 2 and 3.
if [[ "${1:-}" == "--all-stages" ]]; then
  # Standalone developers use the per-target layout, while the
  # reproducible CMake bootstrap proof writes to build/self_hosting directly.
  stageDir="build/self_hosting/linux"
  if [[ ! -x "$stageDir/hydrogen-stage1" ]]; then
    stageDir="build/self_hosting"
  fi
  compilers=(
    "$stageDir/hydrogen-stage1"
    "$stageDir/hydrogen-stage2"
    "$stageDir/hydrogen-stage3"
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
# Projects must build from their own checkout, not only from Hydrogen's
# source root. This reproduces: cd Quark-IDE && /path/to/hydrogen-stage1
# build Quark.hyproj, where the GTK4 frontend source is not in the CWD.
case "$compiler" in
  /*) absoluteCompiler="$compiler" ;;
  *) absoluteCompiler="$root/$compiler" ;;
esac
outOfTree="$work/External-stage$index"
(cd "$work" &&
  "$absoluteCompiler" build "$root/samples/ui_studio/Studio.hyproj" -o "$outOfTree" \
    --hide-spinner --hide-log --hide-progress)
test -x "$outOfTree"
test ! -e "$outOfTree.runtime"
"$outOfTree" --help | grep -q 'HYDROGEN_UI_SINGLE_FILE_V1'
# One ELF is delivered. No backend, launcher, runtime folder, document or
# asset file may remain on the filesystem beside the output.
test ! -e "$output.runtime"
test ! -e "$output.ui-staging"
test ! -e "$output.ui-launcher"
test ! -e "$output.ui-backup"
test ! -e "$output.ui-backup.runtime"
file "$output" | grep -q 'ELF 64-bit'
"$output" --help | grep -q 'HYDROGEN_UI_SINGLE_FILE_V1'
if ldd "$output" | grep -q 'Qt6'; then
  echo "Direct GTK4 frontend unexpectedly links to Qt" >&2
  exit 1
fi
ldd "$output" | grep -q 'libgtk-4'
# gtk_application_new and the GTK event loop require a running display.
export GDK_BACKEND=x11
export GTK_A11Y=none
# GTK warnings about invalid widget types must be caught as regressions.
# Treat warnings from container ownership (e.g. GtkListBox removing an
# unsupported popover child) as failures, not just type assertion criticals.
export G_DEBUG=fatal-warnings
# A copied ELF must run without a build tree, SDK, HYUI document, or
# companion folder. The working directory is intentionally unrelated.
relocated="$work/Relocated-Stage$index"
cp -- "$output" "$relocated"
(cd /tmp && "$relocated" --event ShowControls:showControls --state-output "$work/state.json")
python3 - "$work/state.json" <<'PY'
import json
import sys
from pathlib import Path
state=json.loads(Path(sys.argv[1]).read_text())
assert state["pages.value"] == 1, state
# Neither the context menu nor the popover may be mapped on startup.
# A stray GTK4 popover captures pointer input and prevents button clicks,
# resizing and normal window controls from working.
assert state["__hyui.visible_popovers"] == "0", state
assert state["projectName.text"] == "Aurora Notes", state
assert "Ready when you are" in state["status.text"], state
PY
# Validate the real GTK widget classes rather than simply checking that
# their HYUI tags were accepted by the compiler. This catches regressions
# such as rows masquerading as tables or non-scrolling text editors.
"$output" --verify-native-controls --state-output "$work/native-controls.json"
python3 - "$work/native-controls.json" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as stream:
    state=json.load(stream)
assert state["__hyui.native_controls_checked"] is True, state
elements = ["Window","ColumnPanel","RowPanel","ScrollView","GridPanel","Panel","MenuBar","Menu","MenuItem","ContextMenu","Popover","Toolbar","ToolButton","Clipboard","Tabs","Tab","ListBox","Table","RadioGroup","Image","Dialog","Label","Button","Input","SearchInput","PasswordInput","FilePicker","TextArea","CheckBox","Switch","Select","Slider","NumberInput","ProgressBar","Spinner","Separator","Spacer","State","Timer"]
assert len(elements) == 39
for element in elements:
    key = "__hyui.native." + element
    assert state.get(key) is True, f"{element}: {state.get(key)}"
PY
# Exercise the same window-manager close request as the title-bar button.
# GTK's teardown emits change notifications; these must never dispatch an
# event that reads disposed text views, switches, or an empty GtkStack.
# G_DEBUG=fatal-criticals above turns invalid GTK object access into a failure.
timeout --signal=TERM 8s "$output" --self-test-close >"$work/close.stdout" 2>"$work/close.stderr" || {
  echo "Closing the native GTK window failed:" >&2
  # Limit diagnostics: a GTK teardown loop can generate very large logs.
  tail -n 50 "$work/close.stdout" >&2 || true
  tail -n 100 "$work/close.stderr" >&2 || true
  exit 1
}
"$output" --event ShowWorkspace:showWorkspace --state-output "$work/state.json"
python3 - "$work/state.json" <<'PY'
import json
import sys
from pathlib import Path
state=json.loads(Path(sys.argv[1]).read_text())
assert state["pages.value"] == 0, state
PY
# Rebuilding a generated file is supported without a stale runtime directory.
"$compiler" build samples/ui_studio/Studio.hyproj -o "$output" \
  --hide-spinner --hide-log --hide-progress
test -x "$output"
test ! -e "$output.runtime"
echo "Single-file GTK4 application generated, relocated, rebuilt, and dispatched Hydrogen events: $compiler"
done
echo "Native GTK4 single-executable builds passed for ${#compilers[@]} compiler stage(s)."
