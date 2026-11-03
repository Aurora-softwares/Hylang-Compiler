# Default executable target

Hydrogen's self-hosted compiler builds **portable executable projects** (those
whose `.hyproj` has `type = "exe"`) for the operating system that runs the
compiler, unless a target is supplied explicitly.

| Compiler host | Default `type = "exe"` output | Current architecture |
| --- | --- | --- |
| Linux | Linux ELF | x86-64 |
| macOS | macOS Mach-O | x86-64 (also usable with Rosetta 2 on Apple Silicon) |
| Windows | Windows PE | x86-64 |

The compiler detects Windows using its host API and macOS using the Darwin
system name. A Mac running the x86-64 Hydrogen compiler under Rosetta still
defaults to a **macOS** binary, not Linux.

## Usage

```sh
# Build for this machine's OS
hy build samples/hello/Hello.hyproj -o build/Hello
hy compile Hello.hy -o build/Hello

# Build a different OS's binary on purpose
hy build Hello.hyproj --target linux -o build/HelloLinux
hy build Hello.hyproj --target windows -o build/HelloWindows.exe
hy build Hello.hyproj --target macos -o build/HelloMacOS

# Source compilation also allows explicit OS names
hy compile Hello.hy --target linux-x64 -o build/HelloLinux
hy compile Hello.hy --target windows-x64 -o build/HelloWindows.exe
hy compile Hello.hy --target macos-x64 -o build/HelloMacOS
```

Always provide a suitable executable filename; Windows outputs should use the
`.exe` suffix. The `-o` argument specifies the generated file's path and
name for non-UI programs. Native UI packaging adds the appropriate Windows
`.exe` or macOS `.app` extension if needed.

An explicit `--target` has priority over the host default. Explicit project
types like `type = "windows"` and `type = "macos"` retain their platform
meaning even when built on another host. Firmware, kernels, drivers and OS
projects do not use host-executable targeting.

## Native desktop UI

The same host default applies to `type = "exe"` projects declaring a UI:

- Linux: native GTK4 executable (single ELF).
- Windows: native WinUI 3 executable.
- macOS: native AppKit application (`.app`).

Native UI SDKs/build dependencies still depend on the platform. Cross-platform
UI builds may require exported runtime SDKs via `--ui-sdk`; changing the
target alone does not install the other platform's native frameworks.

## Verification

Use `python3 tests/targets/test-host-default.py <path-to-hydrogen-stage1>`
(or `python` on Windows) to check the host default and explicit overrides
through output-file magic numbers. The CI workflow exercises Linux, macOS
and Windows separately.
