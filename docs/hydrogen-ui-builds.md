# Building native desktop UI applications with Hydrogen

Hydrogen Stage 1 handles UI application validation, backend compilation, and
native package assembly through the normal `build` command. The separate
`hyui --package` tool is **not required** for these builds.

## Linux (GTK4)

From a bootstrapped compiler checkout with the native UI SDK installed:

```sh
./build/self_hosting/linux/hydrogen-stage1 build samples/ui_studio/Studio.hyproj -o build/Studio
./build/Studio
```

The resulting `build/Studio` launcher needs the adjacent
`build/Studio.runtime/` directory. GTK4 is a native system dependency.
The UI SDK build requires Qt Core 6.8+ for the *nonvisual* native host;
the displayed controls are GTK4, not Qt-styled replacements.

The clean bootstrap attempts to build `hyui-native` and
`hyui-launcher` as UI **runtime** components if the required Qt version is
available. They are not separate application-packaging commands.

## Windows (WinUI 3)

A clean Windows bootstrap with .NET 8+ can export the target SDK without
Qt or the legacy `hyui` packager. Alternatively:

```powershell
cmake -S . -B build/ui-sdk -DHYDROGEN_BUILD_UI=OFF
cmake --build build/ui-sdk --target hydrogen-ui-sdk --config Release
```

The SDK appears in `build/ui-sdk/native-sdk/windows-x64/`. Use this
directory's **parent** as `--ui-sdk`:

```sh
hy build samples/ui_studio/Studio.hyproj --target windows --ui-sdk build/ui-sdk/native-sdk -o build/Studio
```

The generated `Studio.exe` requires its adjacent
`Studio.exe.runtime/` directory. The exported host uses real WinUI 3.

## macOS (AppKit)

Export an **x86-64** SDK on macOS with x86-64 Qt 6.8+ and `macdeployqt`:

```sh
cmake -S . -B build/ui-sdk -DHYDROGEN_BUILD_UI=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_PREFIX_PATH=/path/to/x64/Qt
cmake --build build/ui-sdk --target hydrogen-ui-sdk --parallel
```

The SDK appears in `build/ui-sdk/native-sdk/macos-x64.app`. The
`-DCMAKE_OSX_ARCHITECTURES=x86_64` option matters especially on Apple
Silicon Macs; exporting an arm64-only host as x64 is rejected.

```sh
hy build samples/ui_studio/Studio.hyproj --target macos --ui-sdk build/ui-sdk/native-sdk -o build/Studio
```

The result is `build/Studio.app`, using native AppKit controls.
App bundles intended for distribution may additionally require Apple
codesigning and notarization.

## Cross-compilation

A Linux Hydrogen compiler can build Windows and macOS backends, but
**native UI runtimes must originate from the corresponding target OS**.
Export the SDK on Windows/macOS and provide it via `--ui-sdk` on the build
machine. The compiler cannot invent a working WinUI or AppKit runtime
from GTK libraries.

An exported SDK root may contain `windows-x64/` and/or
`macos-x64.app/`. The runtime is copied into the output package;
it is not needed on the end user's machine outside that package.

## Project manifest

```toml
format = 2
name = "MyApp"
version = "0.1.0"
type = "exe"
ui = "App.hyui"
ui_assets = ["assets"]
sources = ["Program.hy"]
project_references = ["../../libraries/Hydrogen.UI/Hydrogen.UI.hyproj"]
```

For a normal native desktop build use `type = "exe"`. For a specific
cross-target use `--target windows` or `--target macos`.

## Boundaries

- One developer-facing `hy build` command does **not** mean the compiled
  application is one physical file: the Linux/Windows runtime directory
  and macOS application bundle remain required.
- Linux/macOS document validation currently reuses the **native runtime**
  validator; a full pure-Hydrogen XML validator is still future work.
- `hy ui <project.hyproj>` uses Hydrogen's integrated build path.
  The older `hy ui <file.hy>` single-source preview still uses its
  legacy UI host until transient-project support has been ported.
- The compiler's Stage 0 bootstrap still uses its C++ seed. The
  developer-facing Stage 1 compiler and UI build orchestration are
  self-hosted Hydrogen.
