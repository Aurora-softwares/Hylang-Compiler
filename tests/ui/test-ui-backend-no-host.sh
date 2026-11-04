#!/usr/bin/env bash
# Verify that Hydrogen can compile the HYUI application backend without any
# native UI SDK, Qt installation or hyui-native validation executable.
# This is NOT a runnable graphical UI integration test.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

# An intentionally empty SDK path prevents accidental use of a locally
# installed Qt/native UI host during this compiler-only regression test.
sdk="$work/no-native-host"
mkdir -p "$sdk"

if [[ "${1:-}" == "--compiler" ]]; then
    if [[ $# -ne 2 ]]; then echo "usage: $0 [--compiler <stage-binary>]" >&2; exit 2; fi
    stages=("$2")
else
    stages=(
        "$root/build/self_hosting/linux/hydrogen-stage1"
        "$root/build/self_hosting/linux/hydrogen-stage2"
        "$root/build/self_hosting/linux/hydrogen-stage3"
    )
fi

# The broken document must fail compiler-side preflight, even without the Qt
# validation tool. The program source is deliberately absent: a well-ordered
# build rejects the document before attempting backend compilation.
cat >"$work/Broken.hyproj" <<'EOF'
format = 2
name = "BrokenUi"
type = "exe"
sources = ["Nonexistent.hy"]
ui = "Broken.hyui"
EOF
printf '%s\n' '<Window version="1"><Label id="test"></Window>' >"$work/Broken.hyui"

index=0
for compiler in "${stages[@]}"; do
    index=$((index + 1))
    if [[ ! -x "$compiler" ]]; then
        echo "Missing executable compiler: $compiler" >&2
        exit 1
    fi

    output="$work/HydrogenStudio-$index"
    "$compiler" build "$root/samples/ui_studio/Studio.hyproj" \
        -o "$output" --ui-backend --ui-sdk "$sdk" \
        --hide-progress --hide-spinner --hide-log
    if [[ ! -x "$output" ]]; then
        echo "Hydrogen backend was not generated: $output" >&2
        exit 1
    fi
    if [[ -e "$output.runtime" || -e "$output.ui-staging" ]]; then
        echo "Compiler-only build unexpectedly created a UI host package" >&2
        exit 1
    fi
    # The backend must actually execute generated Hydrogen logic. It is not a
    # graphical application until the native event loop is linked in-process.
    startup="$("$output")"
    if ! printf '%s\n' "$startup" | grep -Fq "$(printf 'HYUI\tOPEN\tStudio.hyui')"; then
        echo "Compiled Hydrogen UI backend did not execute Application.Open" >&2
        exit 1
    fi

    # Every stage must reject malformed UI before trying to compile the
    # deliberately missing source file. Match the parser diagnostic, not
    # merely a nonzero exit status.
    check_invalid() {
        local source="$1" expected="$2"
        printf '%s\n' "$source" >"$work/Broken.hyui"
        if "$compiler" build "$work/Broken.hyproj" \
            -o "$work/invalid-$index" --ui-backend --ui-sdk "$sdk" \
            --hide-progress --hide-spinner --hide-log >"$work/invalid.log" 2>&1; then
            echo "Compiler accepted invalid HYUI: $compiler: $source" >&2
            exit 1
        fi
        if ! grep -Fq -- "$expected" "$work/invalid.log"; then
            echo "Expected UI preflight error '$expected', got:" >&2
            cat "$work/invalid.log" >&2
            exit 1
        fi
    }
    check_invalid '<Window version="1"><Label id="test"></Window>' 'mismatched closing element'
    check_invalid '<Window version="1"><Mystery/></Window>' 'unsupported UI element'
    check_invalid '<Window version="1"><Label id="duplicate"/><Label id="duplicate"/></Window>' 'duplicate UI element id'
    check_invalid '<Window version="1"><Button onClicked="Clicked"/></Window>' 'unsupported or oversized attribute'
    check_invalid '<Window version="1"><Tabs><Button text="Bad"/></Tabs></Window>' 'invalid placement'
    check_invalid '<Window version="1"><Button onClick="Run()"/></Window>' 'invalid handler name'
    check_invalid '<Window version="1"><Button visible="maybe"/></Window>' 'must be true or false'
    check_invalid '<Window><Label text="Missing version"/></Window>' 'Window requires version'
    check_invalid '<Window version="1"><FilePicker mode="read" text="Open" onPick="Pick"/></Window>' 'FilePicker requires mode'
    check_invalid '<Window version="1"><Timer interval="10" onTick="Tick"/></Window>' 'invalid numeric'
    check_invalid '<Window version="1"><Toolbar><ToolButton text="No handler"/></Toolbar></Window>' 'ToolButton requires text and onClick'
    echo "HYUI native-free schema and backend passed: $compiler"
done

echo "Hydrogen UI backend compilation passed without hyui-native."
