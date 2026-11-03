#!/usr/bin/env bash
# Run with Xvfb. This builds a native GTK4 executable from Hydrogen alone:
# no c++, gcc, g++, ld, tar, objcopy, hyui-native or source-root lookup.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
compiler="${1:-$root/build/self_hosting/linux/hydrogen-stage1}"
[[ -x "$compiler" ]] || { echo "missing compiler: $compiler" >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
# Always invoke Hydrogen outside its source checkout.
cd "$work"
"$compiler" build "$root/samples/native_gtk/NativeGtk.hyproj" -o "$work/app" \
  --hide-spinner --hide-log --hide-progress
test -x "$work/app"
test ! -e "$work/app.runtime"
test ! -e "$work/app.ui-staging"
file "$work/app" | grep -q 'ELF 64-bit'
readelf -d "$work/app" | grep -q 'libgtk-4.so.1'
ldd "$work/app" | grep -q 'libgtk-4.so.1'
if ldd "$work/app" | grep -q 'not found'; then
  echo "Missing runtime library" >&2
  exit 1
fi
# Emit the real GTK "clicked" signal and prove Hydrogen observes its
# native callback without a separate child backend or IPC.
"$work/app" --self-test-click >"$work/click-out" 2>"$work/click-error" || {
  cat "$work/click-out" "$work/click-error" >&2
  exit 1
}
grep -q 'HYDROGEN_NATIVE_GTK_CLICKED' "$work/click-out"
set +e
timeout --signal=TERM 4s "$work/app" >"$work/stdout" 2>"$work/stderr"
result=$?
set -e
test "$result" -eq 124 || {
  echo "Hydrogen native GTK window terminated early: $result" >&2
  cat "$work/stdout" "$work/stderr" >&2
  exit 1
}
grep -q 'HYDROGEN_NATIVE_GTK_READY' "$work/stdout" || {
  cat "$work/stdout" "$work/stderr" >&2
  exit 1
}
echo "Hydrogen-only GTK4 window was built, linked, started and remained responsive."
