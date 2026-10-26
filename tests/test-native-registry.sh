#!/usr/bin/env bash
set -euo pipefail
hy=${1:?pass compiled native hy}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/registry/packages/alpha/1.0.0" "$work/registry/packages/alpha/1.1.0" "$work/registry/packages/beta/2.0.0"
mkdir -p "$work/source/alpha" "$work/source/beta" "$work/app"
cat > "$work/source/alpha/alpha.hyproj" <<'EOF'
format = 2
type = "lib"
version = "1.0.0"
sources = ["Alpha.hy"]
[dependencies]
beta = "2.0.0"
[package]
id = "alpha"
EOF
cat > "$work/source/alpha/Alpha.hy" <<'EOF'
namespace Alpha { public class Value { public static string Text() { return Beta.Value.Text(); } } }
EOF
cat > "$work/source/beta/beta.hyproj" <<'EOF'
format = 2
type = "lib"
version = "2.0.0"
sources = ["Beta.hy"]
[package]
id = "beta"
EOF
cat > "$work/source/beta/Beta.hy" <<'EOF'
namespace Beta { public class Value { public static string Text() { return "remote graph ok"; } } }
EOF
cat > "$work/app/App.hyproj" <<'EOF'
format = 2
type = "exe"
sources = ["Program.hy"]
EOF
cat > "$work/app/Program.hy" <<'EOF'
public class Program { public static int Main(string[] args) { System.Console.WriteLine(Alpha.Value.Text()); return 0; } }
EOF
"$hy" package pack "$work/source/alpha/alpha.hyproj" -o "$work/registry/packages/alpha/1.0.0/alpha-1.0.0.hypkg" >/dev/null
"$hy" package pack "$work/source/beta/beta.hyproj" -o "$work/registry/packages/beta/2.0.0/beta-2.0.0.hypkg" >/dev/null
sed -i 's/version = "1.0.0"/version = "1.1.0"/' "$work/source/alpha/alpha.hyproj"
"$hy" package pack "$work/source/alpha/alpha.hyproj" -o "$work/registry/packages/alpha/1.1.0/alpha-1.1.0.hypkg" >/dev/null
{
    printf 'hydrogen-registry-v1\n'
    for entry in alpha/1.0.0/alpha-1.0.0 alpha/1.1.0/alpha-1.1.0 beta/2.0.0/beta-2.0.0; do
        id=${entry%%/*}; rest=${entry#*/}; version=${rest%%/*}
        archive="$work/registry/packages/$entry.hypkg"
        printf '%s %s %s\n' "$id" "$version" "$(sha256sum "$archive" | cut -d' ' -f1)"
    done
} > "$work/registry/index.txt"
registry="file://$work/registry"
"$hy" package search alpha --registry "$registry" > "$work/search.log"
grep -Fxq 'alpha@1.0.0' "$work/search.log"
grep -Fxq 'alpha@1.1.0' "$work/search.log"
"$hy" package add "$work/app/App.hyproj" alpha@1.0.0 --registry "$registry" > "$work/add.log"
grep -Fq 'alpha = "1.0.0"' "$work/app/App.hyproj"
if grep -Fq 'beta = "2.0.0"' "$work/app/App.hyproj"; then echo 'transitive dependency became direct' >&2; exit 1; fi
grep -Fq 'package beta 2.0.0 ' "$work/app/hy.lock"
"$hy" build "$work/app/App.hyproj" -o "$work/app/main" --hide-progress --hide-spinner --hide-log >/dev/null
chmod +x "$work/app/main"
[[ $("$work/app/main") == 'remote graph ok' ]]
rm -rf -- "$work/app/.hylang/packages"
"$hy" package restore "$work/app/App.hyproj" --registry "$registry" > "$work/restore.log"
"$hy" build "$work/app/App.hyproj" -o "$work/app/restored" --hide-progress --hide-spinner --hide-log >/dev/null
chmod +x "$work/app/restored"
[[ $("$work/app/restored") == 'remote graph ok' ]]
"$hy" package upgrade "$work/app/App.hyproj" alpha@1.1.0 --registry "$registry" > "$work/upgrade.log"
grep -Fq 'alpha = "1.1.0"' "$work/app/App.hyproj"
"$hy" build "$work/app/App.hyproj" -o "$work/app/upgraded" --hide-progress --hide-spinner --hide-log >/dev/null
chmod +x "$work/app/upgraded"
[[ $("$work/app/upgraded") == 'remote graph ok' ]]
sed -i "s/alpha 1.1.0 [0-9a-f]\{64\}/alpha 1.1.0 $(printf '%064d' 0)/" "$work/registry/index.txt"
if "$hy" package restore "$work/app/App.hyproj" --registry "$registry" > "$work/tamper.log" 2>&1; then
    echo 'registry hash tampering unexpectedly passed' >&2; exit 1
fi
echo 'native registry tests passed'
