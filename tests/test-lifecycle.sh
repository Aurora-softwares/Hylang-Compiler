#!/usr/bin/env bash
set -euo pipefail
source_dir=${1:?expected repository root}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
checks=0
check() { checks=$((checks+1)); printf 'ok %d - %s\n' "$checks" "$1"; }
fail() { printf 'not ok - %s\n' "$*" >&2; exit 1; }
assert_failure() {
    if "$@" </dev/null >"$work/stdout" 2>"$work/stderr"; then
        fail "expected failure: $*"
    fi
}

mkdir -p "$work/source/scripts" "$work/mocks" "$work/assets"
cp "$source_dir/scripts/hy-launcher" "$source_dir/scripts/hy-maintenance" "$work/source/scripts/"
cat > "$work/source/LICENSE" <<<'test license'
cat > "$work/source/core" <<'CORE'
#!/usr/bin/env bash
printf 'native compiler invoked: %s\n' "$*"
CORE
chmod +x "$work/source/core"
make_release() {
    cmake -DSOURCE_DIR="$work/source" -DINPUT_BINARY="$work/source/core" -DVERSION="$1" \
          -DRELEASES_DIR="$work/assets" -P "$source_dir/cmake/PackageHydrogenRelease.cmake" >/dev/null
}
make_release 'alpha-0.0.1'
make_release 'alpha-0.0.2'
cd "$work"
mkdir -p installation
( cd installation && tar -xzf "$work/assets/hydrogen-alpha-0.0.1-linux-x86_64.tar.gz" --strip-components=1 )
hy="$work/installation/bin/hy"
[[ $($hy hello world) == 'native compiler invoked: hello world' ]] || fail 'compiler delegation'
[[ $($hy --version) == 'Hydrogen alpha-0.0.1' ]] || fail 'version display'
check 'launcher passes compiler commands and reports release version'
ln -s "$hy" "$work/hy-symlink"
[[ $("$work/hy-symlink" --version) == 'Hydrogen alpha-0.0.1' ]] || fail 'symlink launcher failed'
check 'external launcher symlink can invoke the installed compiler'

# In tests APT ownership is reported only when explicitly enabled. The mock
# operates on temp files and does not touch any real packages.
cat > "$work/mocks/dpkg-query" <<'SH'
#!/usr/bin/env bash
if [[ -n ${MOCK_DPKG_OWNER:-} ]]; then printf '%s: %s\n' "$MOCK_DPKG_OWNER" "${@: -1}"; exit 0; fi
exit 1
SH
cat > "$work/mocks/apt-cache" <<'SH'
#!/usr/bin/env bash
printf 'APT policy %s\n' "$*"
SH
cat > "$work/mocks/apt-get" <<'SH'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$MOCK_LOG"
SH
cat > "$work/mocks/sudo" <<'SH'
#!/usr/bin/env bash
"$@"
SH
cat > "$work/mocks/curl" <<'SH'
#!/usr/bin/env bash
out=''; last="${@: -1}"; args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    if [[ ${args[i]} == '--output' ]]; then out=${args[i+1]}; fi
done
if [[ $last == *'/releases?per_page=100' ]]; then
    cat -- "$MOCK_API_JSON"
else
    [[ -n $out ]] || exit 2
    cp -- "$MOCK_ASSETS/${last##*/}" "$out"
fi
SH
chmod +x "$work/mocks/"*
export PATH="$work/mocks:$PATH" MOCK_ASSETS="$work/assets" MOCK_LOG="$work/mock.log"
unset MOCK_DPKG_OWNER || true

assert_failure "$hy" update-check --force
assert_failure "$hy" update --other
check 'invalid lifecycle flags fail safely'

assert_failure "$hy" uninstall
[[ -f $hy ]] || fail 'uninstall prompt removed installation without confirmation'
check 'manual uninstall requires confirmation in non-interactive use'

export MOCK_DPKG_OWNER=hydrogen-compiler
[[ $($hy update-check) == *'APT policy policy hydrogen-compiler'* ]] || fail 'APT check delegation'
: > "$MOCK_LOG"
"$hy" update --force >/dev/null
[[ $(cat "$MOCK_LOG") == *'apt-get update'* ]] || fail 'APT refresh was not requested'
[[ $(cat "$MOCK_LOG") == *'apt-get install -y --only-upgrade hydrogen-compiler'* ]] || fail 'APT upgrade not delegated'
: > "$MOCK_LOG"
"$hy" uninstall --force >/dev/null
[[ $(cat "$MOCK_LOG") == *'apt-get remove -y hydrogen-compiler'* ]] || fail 'APT removal not delegated'
[[ -f $hy ]] || fail 'package manager path deleted files directly'
check 'APT ownership delegates all operations and never deletes package files'
unset MOCK_DPKG_OWNER

cat > "$work/mocks/rpm" <<'SH'
#!/usr/bin/env bash
if [[ -n ${MOCK_RPM_OWNER:-} ]]; then echo "$MOCK_RPM_OWNER"; exit 0; fi
exit 1
SH
cat > "$work/mocks/dnf" <<'SH'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >> "$MOCK_LOG"
if [[ $1 == check-update ]]; then exit 100; fi
SH
chmod +x "$work/mocks/rpm" "$work/mocks/dnf"
export MOCK_RPM_OWNER=hydrogen-rpm
"$hy" update-check >/dev/null
: > "$MOCK_LOG"
"$hy" update --force >/dev/null
[[ $(cat "$MOCK_LOG") == 'dnf -y upgrade hydrogen-rpm' ]] || fail 'RPM update delegation'
check 'RPM/DNF ownership delegates update and accepts check-update exit code 100'
export MOCK_DPKG_OWNER=hydrogen-compiler
assert_failure "$hy" uninstall --force
[[ $(cat "$work/stderr") == *'ambiguous package ownership'* ]] || fail 'ownership conflict was not detected'
check 'mixed package manager ownership is rejected'
unset MOCK_RPM_OWNER MOCK_DPKG_OWNER

cat > "$work/mocks/pacman" <<'SH'
#!/usr/bin/env bash
case "$1" in
    -Qqo) [[ -n ${MOCK_PACMAN_OWNER:-} ]] || exit 1; echo "$MOCK_PACMAN_OWNER" ;;
    -Qu) echo 'hydrogen-pacman 0.1 -> 0.2' ;;
    *) printf 'pacman %s\n' "$*" >> "$MOCK_LOG" ;;
esac
SH
chmod +x "$work/mocks/pacman"
export MOCK_PACMAN_OWNER=hydrogen-pacman
[[ $($hy update-check) == *'hydrogen-pacman 0.1'* ]] || fail 'pacman update check'
: > "$MOCK_LOG"
"$hy" update --force >/dev/null
[[ $(cat "$MOCK_LOG") == 'pacman --noconfirm -Syu hydrogen-pacman' ]] || fail 'pacman update delegation'
: > "$MOCK_LOG"
"$hy" uninstall --force >/dev/null
[[ $(cat "$MOCK_LOG") == 'pacman --noconfirm -R hydrogen-pacman' ]] || fail 'pacman removal delegation'
[[ -e $hy ]] || fail 'pacman package was deleted directly'
check 'Pacman-owned installation uses the native manager for updates/removal'
unset MOCK_PACMAN_OWNER

mkdir -p "$work/Cellar/hydrogen-brew/0.1" 
( cd "$work/Cellar/hydrogen-brew/0.1" && tar -xzf "$work/assets/hydrogen-alpha-0.0.1-linux-x86_64.tar.gz" --strip-components=1 )
brew_hy="$work/Cellar/hydrogen-brew/0.1/bin/hy"
cat > "$work/mocks/brew" <<'SH'
#!/usr/bin/env bash
case "$1" in
    --cellar) echo "$MOCK_BREW_CELLAR" ;;
    list) echo 'hydrogen-brew 0.1' ;;
    *) printf 'brew %s\n' "$*" >> "$MOCK_LOG" ;;
esac
SH
chmod +x "$work/mocks/brew"
export MOCK_BREW_CELLAR="$work/Cellar"
: > "$MOCK_LOG"
"$brew_hy" update-check >/dev/null
"$brew_hy" update --force >/dev/null
"$brew_hy" uninstall --force >/dev/null
[[ $(cat "$MOCK_LOG") == *'brew outdated --formula hydrogen-brew'* ]] || fail 'brew outdated not delegated'
[[ $(cat "$MOCK_LOG") == *'brew upgrade hydrogen-brew'* ]] || fail 'brew update not delegated'
[[ $(cat "$MOCK_LOG") == *'brew uninstall hydrogen-brew'* ]] || fail 'brew remove not delegated'
[[ -e $brew_hy ]] || fail 'brew release was deleted directly'
check 'Homebrew cellar ownership delegates update/check/removal'

# Generate authentic-looking local release API fixtures to drive the full
# manual-update pipeline with a mocked curl; no live network is used.
archive='hydrogen-alpha-0.0.2-linux-x86_64.tar.gz'
digest=$(sha256sum "$work/assets/$archive"); digest=${digest%% *}
export MOCK_API_JSON="$work/releases.json"
cat > "$MOCK_API_JSON" <<EOFJSON
[
 {"tag_name":"alpha-0.0.2","draft":false,"prerelease":true,"published_at":"2026-10-25T00:00:00Z",
  "assets":[
    {"name":"$archive","digest":"sha256:$digest","browser_download_url":"https://github.com/Aurora-softwares/Hylang-Compiler/releases/download/alpha-0.0.2/$archive"},
    {"name":"$archive.sha256","browser_download_url":"https://github.com/Aurora-softwares/Hylang-Compiler/releases/download/alpha-0.0.2/$archive.sha256"}
  ]},
 {"tag_name":"alpha-0.0.1","draft":false,"prerelease":true,"published_at":"2026-10-20T00:00:00Z", "assets":[]}
]
EOFJSON
[[ $($hy update-check) == *'Update available.'* ]] || fail 'manual update-check'
check 'manual update-check chooses the current release channel'

# Force an integrity failure before installation; verify old release untouched.
sed "s/sha256:$digest/sha256:$(printf '0%.0s' {1..64})/" "$MOCK_API_JSON" > "$work/bad.json"
MOCK_API_JSON="$work/bad.json" assert_failure "$hy" update --force
[[ $($hy --version) == 'Hydrogen alpha-0.0.1' ]] || fail 'bad digest modified installation'
check 'digest failure preserves the previous compiler'

cp "$work/assets/$archive.sha256" "$work/original.sha256"
printf '%064d  %s\n' 0 "$archive" > "$work/assets/$archive.sha256"
assert_failure "$hy" update --force
[[ $($hy --version) == 'Hydrogen alpha-0.0.1' ]] || fail 'invalid sidecar modified installation'
cp "$work/original.sha256" "$work/assets/$archive.sha256"
check 'published sidecar mismatch fails closed'

echo 'user work' > "$work/installation/notes.txt"
assert_failure "$hy" update --force
[[ $($hy --version) == 'Hydrogen alpha-0.0.1' ]] || fail 'unknown files were overwritten'
assert_failure "$hy" uninstall --force
[[ -f "$work/installation/notes.txt" ]] || fail 'user file lost'
rm "$work/installation/notes.txt"
check 'unknown files block both replacement and uninstall'

"$hy" update --force > "$work/update.log"
[[ $($hy --version) == 'Hydrogen alpha-0.0.2' ]] || fail 'upgrade version mismatch'
[[ $($hy tokens file.hy) == 'native compiler invoked: tokens file.hy' ]] || fail 'compiler stopped working after upgrade'
check 'verified manual update switches to new release'

[[ $($hy update-check) == *'No newer release on this channel.'* ]] || fail 'up to date check'
assert_failure "$hy" update-check --force
check 'up-to-date version is detected'

"$hy" remove --force >/dev/null
[[ ! -e $hy ]] || fail 'uninstall did not remove its own files'
[[ ! -e $work/installation ]] || fail 'uninstall left empty release root'
check 'remove/uninstall deletes only files from a trusted manifest'
mkdir -p "$work/home/.local/share/hydrogen" "$work/home/.local/bin"
( cd "$work/home/.local/share/hydrogen" && tar -xzf "$work/assets/hydrogen-alpha-0.0.2-linux-x86_64.tar.gz" --strip-components=1 )
ln -s "$work/home/.local/share/hydrogen/bin/hy" "$work/home/.local/bin/hy"
HOME="$work/home" "$work/home/.local/bin/hy" uninstall --force >/dev/null
[[ ! -e $work/home/.local/share/hydrogen && ! -L $work/home/.local/bin/hy ]] ||
    fail 'website installer launcher remained after uninstall'
check 'standalone uninstall removes the website installer launcher it owns'
printf 'ALL %d LIFECYCLE CHECKS PASSED\n' "$checks"
