#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hydrogen-macos-integration"
mkdir -p "$build_dir"

cmake -S "$source_dir" -B "$build_dir/bootstrap" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir/bootstrap" --target hy --parallel 2

# Stage 0 emits host C only to seed Hydrogen's self-hosted compiler.
"$build_dir/bootstrap/hy" build \
    "$source_dir/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.hyproj" \
    -o "$build_dir/hydrogen-bootstrap"
"$build_dir/hydrogen-bootstrap" build \
    "$source_dir/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.MacOS.hyproj" \
    -o "$build_dir/hydrogen-macos-stage1" --hide-progress --hide-spinner --hide-log
chmod +x "$build_dir/hydrogen-macos-stage1"
file "$build_dir/hydrogen-macos-stage1"

"$build_dir/hydrogen-macos-stage1" build \
    "$source_dir/src/Hydrogen.Compiler.Cli/Hydrogen.Compiler.Cli.MacOS.hyproj" \
    -o "$build_dir/hydrogen-macos-stage2" --hide-progress --hide-spinner --hide-log
chmod +x "$build_dir/hydrogen-macos-stage2"
cmp "$build_dir/hydrogen-macos-stage1" "$build_dir/hydrogen-macos-stage2"

"$build_dir/hydrogen-macos-stage2" new macos "$build_dir/scaffold"
"$build_dir/hydrogen-macos-stage2" check "$build_dir/scaffold/scaffold.hyproj"
"$build_dir/hydrogen-macos-stage2" build "$build_dir/scaffold/scaffold.hyproj" \
    -o "$build_dir/scaffold-app" --hide-progress --hide-spinner --hide-log
chmod +x "$build_dir/scaffold-app"
test "$("$build_dir/scaffold-app")" = 'Hello from scaffold!'

"$build_dir/hydrogen-macos-stage2" compile \
    "$source_dir/tests/macos/Hello.hy" --target macos-x64 \
    -o "$build_dir/hello"
chmod +x "$build_dir/hello"
hello_output=$("$build_dir/hello")
test "$hello_output" = 'Hello from Hydrogen on macOS!'

"$build_dir/hydrogen-macos-stage2" build \
    "$source_dir/tests/macos/FullRuntime.hyproj" \
    -o "$build_dir/full-runtime" --hide-progress --hide-spinner --hide-log
chmod +x "$build_dir/full-runtime"
set +e
runtime_output=$("$build_dir/full-runtime" "$build_dir/subdir/macos-é.txt" 'two words')
runtime_status=$?
set -e
test "$runtime_status" -eq 42
test "$runtime_output" = 'macOS runtime parity ok'

"$build_dir/hydrogen-macos-stage2" compile \
    "$source_dir/tests/phase6/native_runtime_files.hy" --target macos-x64 \
    -o "$build_dir/runtime-files"
chmod +x "$build_dir/runtime-files"
set +e
files_output=$("$build_dir/runtime-files" "$build_dir/macos-runtime.bin")
files_status=$?
set -e
test "$files_status" -eq 42
test "$files_output" = 'files and GC ok'

"$build_dir/hydrogen-macos-stage2" compile \
    "$source_dir/tests/phase6/native_host_process.hy" --target macos-x64 \
    -o "$build_dir/host-process"
chmod +x "$build_dir/host-process"
set +e
"$build_dir/host-process" 'exit 7'
process_status=$?
set -e
test "$process_status" -eq 7

cmake -DSOURCE_DIR="$source_dir" -DHOST_COMPILER="$build_dir/hydrogen-macos-stage2" \
    -DVERSION=alpha-0.0.0-macos-ci -DRELEASES_DIR="$build_dir/releases" \
    -P "$source_dir/cmake/MakeHydrogenMacOSRelease.cmake"
archive="$build_dir/releases/hydrogen-alpha-0.0.0-macos-ci-macos-x86_64.tar.gz"
test -f "$archive.sha256"
mkdir -p "$build_dir/installed"
tar -xzf "$archive" -C "$build_dir/installed"
package="$build_dir/installed/hydrogen-alpha-0.0.0-macos-ci-macos-x86_64"
test "$("$package/bin/hy" --version)" = 'Hydrogen alpha-0.0.0-macos-ci'
"$package/bin/hy" check "$source_dir/tests/macos/FullRuntime.hyproj"
"$package/bin/hy" uninstall --force
test ! -e "$package"

echo 'macOS x64 self-hosting, runtime, CLI, release, and uninstall passed'
