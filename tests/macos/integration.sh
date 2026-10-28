#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/hydrogen-macos-integration.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT

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

mkdir -p "$build_dir/library"
cat > "$build_dir/library/mac.library.hyproj" <<'EOF'
format = 2
name = "MacLibrary"
version = "1.0.0"
type = "lib"
sources = ["Library.hy"]
[package]
id = "mac.library"
EOF
cat > "$build_dir/library/Library.hy" <<'EOF'
namespace MacLibrary {
    public class Value {
        public static string Text() { return "macOS package ok"; }
    }
}
EOF
"$build_dir/hydrogen-macos-stage2" package pack \
    "$build_dir/library/mac.library.hyproj" -o "$build_dir/library.hypkg"
"$build_dir/hydrogen-macos-stage2" package add \
    "$build_dir/scaffold/scaffold.hyproj" "$build_dir/library.hypkg"
cat > "$build_dir/scaffold/Program.hy" <<'EOF'
public class Program {
    public static int Main(string[] args) {
        System.Console.WriteLine(MacLibrary.Value.Text());
        return 0;
    }
}
EOF
"$build_dir/hydrogen-macos-stage2" build "$build_dir/scaffold/scaffold.hyproj" \
    -o "$build_dir/package-app" --hide-progress --hide-spinner --hide-log
chmod +x "$build_dir/package-app"
test "$("$build_dir/package-app")" = 'macOS package ok'
"$build_dir/hydrogen-macos-stage2" package remove \
    "$build_dir/scaffold/scaffold.hyproj" mac.library
if grep -Fq 'mac.library = ' "$build_dir/scaffold/scaffold.hyproj"; then
    echo 'package removal left the dependency in the manifest' >&2
    exit 1
fi

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

cmake -DSOURCE_DIR="$source_dir" -DINPUT_BINARY="$build_dir/hydrogen-macos-stage2" \
    -DVERSION=alpha-0.0.1-macos-ci -DPLATFORM=macos-x86_64 \
    -DRELEASES_DIR="$build_dir/releases" \
    -P "$source_dir/cmake/PackageHydrogenRelease.cmake"
next_name=hydrogen-alpha-0.0.1-macos-ci-macos-x86_64.tar.gz
next_digest=$(shasum -a 256 "$build_dir/releases/$next_name" | cut -d' ' -f1)
cat > "$build_dir/releases.json" <<EOF
[{"tag_name":"alpha-0.0.1-macos-ci","draft":false,"prerelease":true,"assets":[
{"name":"$next_name","digest":"sha256:$next_digest","browser_download_url":"https://github.com/Aurora-softwares/Hylang-Compiler/releases/download/alpha-0.0.1-macos-ci/$next_name"},
{"name":"$next_name.sha256","browser_download_url":"https://github.com/Aurora-softwares/Hylang-Compiler/releases/download/alpha-0.0.1-macos-ci/$next_name.sha256"}]}]
EOF
mkdir -p "$build_dir/mock-bin"
cat > "$build_dir/mock-bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=''
last=''
while (( $# )); do
    if [[ $1 == --output ]]; then output=$2; shift 2; continue; fi
    last=$1; shift
done
case $last in
    *'/releases?per_page=100') cat "$HY_MACOS_TEST_ROOT/releases.json" ;;
    *.tar.gz.sha256) cp "$HY_MACOS_TEST_ROOT/releases/$HY_MACOS_TEST_ARCHIVE.sha256" "$output" ;;
    *.tar.gz) cp "$HY_MACOS_TEST_ROOT/releases/$HY_MACOS_TEST_ARCHIVE" "$output" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$build_dir/mock-bin/curl"
export HY_MACOS_TEST_ROOT="$build_dir" HY_MACOS_TEST_ARCHIVE="$next_name"
export PATH="$build_dir/mock-bin:$PATH"
"$package/bin/hy" update-check
"$package/bin/hy" update --force
test "$("$package/bin/hy" --version)" = 'Hydrogen alpha-0.0.1-macos-ci'
"$package/bin/hy" uninstall --force
test ! -e "$package"

echo 'macOS x64 self-hosting, runtime, CLI, packages, release, update, and uninstall passed'
