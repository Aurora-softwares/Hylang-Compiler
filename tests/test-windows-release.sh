#!/usr/bin/env bash
set -euo pipefail
source_dir=${1:?expected source directory}
native_binary=${2:?expected native compiler}
wine_binary=${3:?expected Wine binary}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
version=alpha-0.0.3
project="$source_dir/samples/self_hosting/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.Windows.hyproj"
"$native_binary" build "$project" -o "$work/hy-core.exe" --hide-progress >"$work/build.log"
cmake -DSOURCE_DIR="$source_dir" -DINPUT_BINARY="$work/hy-core.exe" \
    -DVERSION="$version" -DRELEASES_DIR="$work/releases" \
    -P "$source_dir/cmake/PackageHydrogenWindowsRelease.cmake" >"$work/package.log"
archive="hydrogen-$version-windows-x86_64.zip"
(cd "$work/releases" && sha256sum -c "$archive.sha256")
unzip -q "$work/releases/$archive" -d "$work/extracted"
root="$work/extracted/hydrogen-$version-windows-x86_64"
[[ -f "$root/libexec/hy-maintenance.ps1" && -f "$root/INSTALL-MANIFEST" ]] ||
    { echo 'Windows release layout incomplete' >&2; exit 1; }
(cd "$root" && sha256sum -c SHA256SUMS)
launcher=$(winepath -w "$root/bin/hy.cmd")
version_output=$(WINEDEBUG=-all "$wine_binary" cmd /c "$launcher --version" | tr -d '\r')
[[ $version_output == "Hydrogen $version" ]] ||
    { echo "Windows launcher version failed: $version_output" >&2; exit 1; }
hash_output=$(cd "$root" && WINEDEBUG=-all "$wine_binary" cmd /c "$launcher package hash LICENSE" | tr -d '\r')
expected=$(sha256sum "$root/LICENSE")
[[ $hash_output == "${expected%% *}" ]] ||
    { echo 'Windows launcher did not delegate to native compiler' >&2; exit 1; }
echo 'Windows release layout, checksums, launcher, and native delegation passed under Wine'
