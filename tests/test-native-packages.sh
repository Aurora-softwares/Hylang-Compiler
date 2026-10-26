#!/usr/bin/env bash
set -euo pipefail

hy=${1:?pass the compiled native hy binary}
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/.hylang/packages/alpha/1.0.0" "$work/.hylang/packages/beta/2.0.0"
printf abc > "$work/hash-vector"
[[ $("$hy" package hash "$work/hash-vector") == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ]]

cat > "$work/App.hyproj" <<'EOF'
format = 2
type = "exe"
sources = ["Program.hy"]

[dependencies]
alpha = "1.0.0"
EOF
cat > "$work/Program.hy" <<'EOF'
public class Program {
    public static int Main(string[] args) {
        System.Console.WriteLine(Alpha.Value.Text());
        return 0;
    }
}
EOF
cat > "$work/.hylang/packages/alpha/1.0.0/alpha.hyproj" <<'EOF'
format = 2
type = "lib"
version = "1.0.0"
sources = ["Alpha.hy"]

[dependencies]
beta = "2.0.0"

[package]
id = "alpha"
EOF
cat > "$work/.hylang/packages/alpha/1.0.0/Alpha.hy" <<'EOF'
namespace Alpha {
    public class Value {
        public static string Text() { return Beta.Value.Text(); }
    }
}
EOF
cat > "$work/.hylang/packages/beta/2.0.0/beta.hyproj" <<'EOF'
format = 2
type = "lib"
version = "2.0.0"
sources = ["Beta.hy"]

[package]
id = "beta"
EOF
cat > "$work/.hylang/packages/beta/2.0.0/Beta.hy" <<'EOF'
namespace Beta {
    public class Value {
        public static string Text() { return "native package graph ok"; }
    }
}
EOF

"$hy" package pack "$work/.hylang/packages/alpha/1.0.0/alpha.hyproj" -o "$work/alpha.hypkg" > "$work/pack.log"
"$hy" package pack "$work/.hylang/packages/beta/2.0.0/beta.hyproj" -o "$work/beta.hypkg" >> "$work/pack.log"
grep -Fqx 'HYLANG_PACKAGE_V1' <(head -n 1 "$work/alpha.hypkg")
grep -Fq 'FILE alpha.hyproj ' "$work/alpha.hypkg"
grep -Fq 'FILE Alpha.hy ' "$work/alpha.hypkg"
cp "$work/alpha.hypkg" "$work/.hylang/packages/alpha/1.0.0/package.hypkg"
cp "$work/beta.hypkg" "$work/.hylang/packages/beta/2.0.0/package.hypkg"
"$hy" package lock "$work/App.hyproj" > "$work/lock.log"
"$hy" build "$work/App.hyproj" -o "$work/app" --hide-progress --hide-spinner --hide-log > "$work/build.log"
chmod +x "$work/app"
[[ $("$work/app") == 'native package graph ok' ]]
cp "$work/hy.lock" "$work/hy.lock.saved"
"$hy" package lock "$work/App.hyproj" > "$work/lock.log"
cmp "$work/hy.lock.saved" "$work/hy.lock"
printf '// tamper\n' >> "$work/.hylang/packages/beta/2.0.0/Beta.hy"
if "$hy" build "$work/App.hyproj" -o "$work/tampered-app" --hide-progress --hide-spinner --hide-log > "$work/lock-error.log" 2>&1; then
    echo 'tampered package source unexpectedly built' >&2
    exit 1
fi
grep -Fq 'hy.lock is missing or does not match' "$work/lock-error.log"
sed -i '$d' "$work/.hylang/packages/beta/2.0.0/Beta.hy"

mkdir "$work/installed"
cp "$work/Program.hy" "$work/installed/Program.hy"
cat > "$work/installed/App.hyproj" <<'EOF'
format = 2
type = "exe"
sources = ["Program.hy"]
EOF
"$hy" package add "$work/installed/App.hyproj" "$work/beta.hypkg" > "$work/add.log"
"$hy" package add "$work/installed/App.hyproj" "$work/alpha.hypkg" >> "$work/add.log"
grep -Fq 'alpha = "1.0.0"' "$work/installed/App.hyproj"
grep -Fq 'beta = "2.0.0"' "$work/installed/App.hyproj"
"$hy" build "$work/installed/App.hyproj" -o "$work/installed/app" --hide-progress --hide-spinner --hide-log > "$work/installed/build.log"
chmod +x "$work/installed/app"
[[ $("$work/installed/app") == 'native package graph ok' ]]
if "$hy" package add "$work/installed/App.hyproj" "$work/alpha.hypkg" > "$work/add-error.log" 2>&1; then
    echo 'duplicate package add unexpectedly succeeded' >&2
    exit 1
fi
grep -Fq 'already declares package alpha' "$work/add-error.log"
"$hy" package remove "$work/installed/App.hyproj" alpha > "$work/remove.log"
if grep -Fq 'alpha = "1.0.0"' "$work/installed/App.hyproj"; then
    echo 'package removal left the direct dependency in the manifest' >&2
    exit 1
fi
grep -Fq 'beta = "2.0.0"' "$work/installed/App.hyproj"
if "$hy" package remove "$work/installed/App.hyproj" alpha > "$work/remove-error.log" 2>&1; then
    echo 'removing a missing dependency unexpectedly succeeded' >&2
    exit 1
fi

cp "$work/alpha.hypkg" "$work/tampered.hypkg"
printf 'FILE ../escape.hy 1\nx\n' >> "$work/tampered.hypkg"
if "$hy" package add "$work/App.hyproj" "$work/tampered.hypkg" > "$work/add-error.log" 2>&1; then
    echo 'unsafe package archive unexpectedly succeeded' >&2
    exit 1
fi
grep -Fq 'unsafe source package entry' "$work/add-error.log"

expect_error() {
    local expected=$1
    if "$hy" build "$work/App.hyproj" -o "$work/bad" --hide-progress --hide-spinner --hide-log > "$work/error.log" 2>&1; then
        echo "expected failure: $expected" >&2
        exit 1
    fi
    grep -Fq "$expected" "$work/error.log" || { cat "$work/error.log" >&2; exit 1; }
}

cp "$work/App.hyproj" "$work/App.original"
printf 'beta = "3.0.0"\n' >> "$work/App.hyproj"
expect_error 'package version conflict for beta'
mv "$work/App.original" "$work/App.hyproj"

mv "$work/.hylang/packages/beta/2.0.0/beta.hyproj" "$work/beta.saved"
expect_error 'project file not found:'
mv "$work/beta.saved" "$work/.hylang/packages/beta/2.0.0/beta.hyproj"

cp "$work/.hylang/packages/beta/2.0.0/beta.hyproj" "$work/beta.original"
sed -i 's/Beta.hy/..\/..\/..\/..\/Program.hy/' "$work/.hylang/packages/beta/2.0.0/beta.hyproj"
expect_error 'package source escapes its directory:'
mv "$work/beta.original" "$work/.hylang/packages/beta/2.0.0/beta.hyproj"

printf '\n[dependencies]\nalpha = "1.0.0"\n' >> "$work/.hylang/packages/beta/2.0.0/beta.hyproj"
expect_error 'package dependency cycle detected'

echo 'native package tests passed'
