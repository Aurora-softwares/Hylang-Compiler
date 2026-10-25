#!/usr/bin/env bash
set -euo pipefail
hy=${1:?pass the native Hydrogen compiler}
source_file=${2:?pass the host-process fixture}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
"$hy" compile "$source_file" -o "$work/linux-process" > "$work/linux-build.log"
chmod +x "$work/linux-process"
set +e
"$work/linux-process"
platform_status=$?
set -e
[[ $platform_status == 3 ]] || { echo "Linux platform status: $platform_status" >&2; exit 1; }
set +e
"$work/linux-process" 'exit 7'
status=$?
set -e
[[ $status == 7 ]] || { echo "Linux process status: $status" >&2; exit 1; }

"$hy" compile "$source_file" --target windows-x64 -o "$work/windows-process.exe" > "$work/windows-build.log"
if command -v wine >/dev/null 2>&1; then
    set +e
    WINEDEBUG=-all wine "$work/windows-process.exe"
    platform_status=$?
    set -e
    [[ $platform_status == 2 ]] || { echo "Wine platform status: $platform_status" >&2; exit 1; }
    set +e
    WINEDEBUG=-all wine "$work/windows-process.exe" 'cmd.exe /c exit 7'
    status=$?
    set -e
    [[ $status == 7 ]] || { echo "Wine process status: $status" >&2; exit 1; }
fi
echo 'host process tests passed'
