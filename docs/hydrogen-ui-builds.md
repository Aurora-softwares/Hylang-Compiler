# Building native desktop UI applications with Hydrogen

Hydrogen Stage 1 handles UI application validation, backend compilation, and
native package assembly through the normal `build` command. The separate
`hyui --package` tool is **not required** for these builds.

## Hydrogen-written native GTK4 (experimental)

Hydrogen now has an initial *Hydrogen-only* Linux GTK4 window-building
path that does not compile or embed a C++ renderer. The self-hosted compiler
generates an ELF with a direct dynamic symbol table, imports GTK4 through the
standard Linux x86-64 ABI, and invokes the native functions from Hydrogen
source. It invokes no external linker, C/C++ compiler, or `hyui-native`
during the application build.

```sh
./build/self_hosting/linux/hydrogen-stage1 build \
  samples/native_gtk/NativeGtk.hyproj -o build/NativeGtk
./build/NativeGtk
```

`libraries/Hydrogen.UI/Window.hy` provides a real GTK window and initial
label/button layout written in Hydrogen. Only system GTK4 runtime libraries
are required to run the compiled application (Ubuntu:
`sudo apt install libgtk-4-1`). Builds are independent of the caller's
working directory. This path is currently an **experimental ABI foundation**,
not yet a full replacement for the established `.hyui` schema. Signal
callbacks, complete widget coverage, renderer and asset embedding, and
Windows/macOS backends still require implementation and parity testing.
The legacy `.hyui` route below remains in place until those features are
available; its C++ GTK host is **not yet removed**.

## Linux (GTK4): one distributable ELF

The default Linux build produces **one ELF file** containing the HYUI
document, resources and Hydrogen-compiled application backend. It needs no
`hyui-native`, `hyui-launcher`, Qt or neighboring `.runtime` folder.
Build the frontend directly with GTK4 development headers and C++ tools:

```sh
sudo apt install build-essential binutils pkg-config libgtk-4-dev
./build/self_hosting/linux/hydrogen-stage1 build samples/ui_studio/Studio.hyproj -o build/Studio
./build/Studio
```

The native frontend is compiled from `tools/hyui/linux_gtk_app.cpp` in
the Hydrogen source checkout: run the UI build from the repository root.
The normal Linux `bootstrap.sh` no longer attempts to build the optional
Qt UI host. Set `HYDROGEN_BUILD_UI=ON` or `HYDROGEN_BOOTSTRAP_UI=on`
to explicitly build the legacy SDK tooling if needed.
GTK4 remains a system runtime dependency. The compiled Hydrogen event backend
is embedded in the ELF and executed through a Linux anonymous `memfd` child
process until in-process Hydrogen native linking is available. This is one
physical file, **not** one process or a fully statically linked GTK program.

For the old host-and-runtime-folder layout, explicitly use an existing Qt
Core 6.8+ SDK via `--ui-sdk build/bootstrap`. The self-hosted
`hy ui validate` and `hy build --ui-backend` paths run preflight without
a native host.

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

- Default Linux builds produce one standalone GTK4 ELF, but system GTK4
  libraries and a child Hydrogen event backend process remain. Windows
  still uses a neighboring runtime directory and macOS a normal
  multi-file application bundle on Development.
- The self-hosted compiler performs bounded lexical UI preflight without
  a native runtime. Full native schema checks can run when an explicit
  native SDK is supplied; the complete Hydrogen validator is future work.
- `hy ui <project.hyproj>` uses Hydrogen's integrated build path.
  The older `hy ui <file.hy>` single-source preview still uses its
  legacy UI host until transient-project support has been ported.
- The compiler's Stage 0 bootstrap still uses its C++ seed. The
  developer-facing Stage 1 compiler and UI build orchestration are
  self-hosted Hydrogen.
