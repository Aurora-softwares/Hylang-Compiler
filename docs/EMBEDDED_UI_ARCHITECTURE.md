# Embedded native UI: compiler and application architecture

## Goal

Each self-hosted compiler stage (Linux/Windows/macOS, where supported) can build native UI projects without invoking a separately installed `hyui` application. The produced graphical application owns its window, UI event loop, and Hydrogen event handlers **in one process**, instead of the current launcher → native host → Hydrogen backend chain.

This is an architectural migration, **not completed by the initial preflight commits**. Dependencies on platform frameworks (GTK4/libadwaita, WinUI 3, AppKit) may remain system or bundled libraries, but should not require a second *application executable*.

## Verified current architecture (Development, 2026-11-02)

- `Hydrogen.Compiler.Cli/Program.hy` dispatches UI projects to `UIProjectBuilder` and `UIPackager`/`UIDesktopPackager`.
- `UIProjectBuilder.Preflight` historically required `build/bootstrap/hyui-native` even for schema validation.
- `UIPackager` builds a Hydrogen backend and copies `hyui-native`, `hyui-launcher`, and Qt dependencies to a `.runtime` directory.
- `tools/hyui/native_runtime.cpp` creates the native UI and reads the declarative `.hyui` document.
- `tools/hyui/bridge.cpp` currently uses `QProcess` to run the Hydrogen backend, including each UI event. This is a separate process, not just a second file.
- `Hydrogen.UI/Application.hy` uses text lines beginning with `HYUI\t` as commands to that process bridge.

## Implemented on this branch

- 🟢 Add `hy ui validate <file.hyui|project.hyproj>` inside the self-hosted compiler.
- 🟢 Allow pure-Hydrogen preflight without requiring `hyui-native`. The native schema checker remains an extra check if installed.
- 🟢 Add `tests/ui/test-stage-ui-preflight.sh` to check Stage 1, 2, and 3.
- 🟢 Require pure-Hydrogen UI preflight before compiling a `--ui-backend` for every supported desktop target.
- 🟢 Add `tests/ui/test-ui-backend-no-host.sh` to build and run the UI app's Hydrogen backend with no native SDK or Qt host. This verifies **code generation and application logic only**, not a graphical window.
- 🟢 On Linux, default `hy build <ui.hyproj>` generates and launches an application-specific native GTK4 executable with no Qt or `hyui-native` dependency. GTK4 development headers and a C++ compiler are presently required at build time.
- 🟢 Linux `hy build <ui.hyproj>` now produces **one relocatable GTK4 ELF** containing the compiled Hydrogen backend, HYUI document and assets. No `.runtime` directory is shipped.
- 🟡 The embedded Hydrogen backend executes from a Linux `memfd` child process for each event. This is **one file, not yet one process**. In-process calls require a Hydrogen native object/linker ABI.
- 🟡 Windows native builds on Windows now use `UIWindowsSinglePackager` to invoke the supported WinUI 3 self-contained `PublishSingleFile` path. The compiler embeds its compiled PE backend and HYUI resources into the published .NET assembly; the app extracts its private data at startup. **CI validation is pending.**
- 🟡 macOS AppKit builds now launch `Contents/MacOS/hyui` as the app's actual `CFBundleExecutable` without `hyui-launcher`. The standard `.app` bundle contains the Qt Core support libraries, UI assets and compiled Hydrogen backend. **This is a single native .app bundle, not a single Mach-O file; CI validation is pending.**
- 🔴 True in-process Hydrogen callbacks remain a separate ABI/linker milestone across Linux, Windows and macOS.
- 🔴 Implement the full native `.hyui` schema in Hydrogen so compilation validates exactly what runtime accepts.
- 🔴 Replace process-based `Bridge` event delivery with **in-process** calls into the compiled Hydrogen application.
- 🔴 Define target-specific UI runtime ABI for Linux GTK4/libadwaita, Windows WinUI 3, and macOS AppKit. Preserve OS theme and controls.
- 🔴 Extend each target compiler/linker to link the appropriate UI entry point and runtime into the generated app rather than generating a launcher/backend pair.
- 🟢 Embed Linux HYUI document/assets and Hydrogen backend ELF into the GTK4 executable through a bounded ustar resource table. Other platform targets remain outstanding.
- 🔴 Remove `hyui-native`/`hyui-launcher` dependency from Linux and desktop packaging paths only after parity tests pass.
- 🟡 The GTK4 single-file test checks ELF relocation, UI event dispatch, rebuilding and no sidecars. Stage 2/3 runs and one-process dispatch remain separate verification gates.
- 🔴 Run bootstrap reproducibility checks and native visual regression tests on supported hosts.

## Acceptance criteria for the final implementation

1. `hydrogen-stageN build samples/ui_studio/Studio.hyproj -o build/ui_studio` succeeds on a clean supported host **without** the `hyui-native` or `hyui-launcher` executable, for N = 1, 2, 3.
2. On Linux, `build/ui_studio` is the complete deployable ELF; no `build/ui_studio.runtime` directory or standalone backend/launcher executable.
3. Native UI controls and all events work in the **same process** as user Hydrogen code. No backend `QProcess` child.
4. Platform-specific native rendering is preserved and system dependencies are stated clearly; one executable does not imply static linking all OS libraries.
5. Unsupported platforms and absent native SDK dependencies fail at build time with specific, actionable errors.
6. No regression to non-UI compilation, stage equivalence, or UI document validation.

## Testing initial preflight work

After bootstrapping:

```sh
./build/self_hosting/linux/hydrogen-stage1 ui validate samples/ui_studio/Studio.hyproj
./build/self_hosting/linux/hydrogen-stage2 ui validate samples/ui_studio/Studio.hyproj
./build/self_hosting/linux/hydrogen-stage3 ui validate samples/ui_studio/Studio.hyproj
bash tests/ui/test-stage-ui-preflight.sh
bash tests/ui/test-ui-backend-no-host.sh
# Requires GTK4 development headers and a graphical display, e.g. Xvfb:
# dbus-run-session -- xvfb-run -a bash tests/ui/test-linux-gtk-direct.sh --all-stages
```

**Current status:** Linux produces one GTK4 ELF and its single-file CI has passed. Windows has a new unpackaged self-contained WinUI 3 single-EXE publishing path; Windows may extract .NET/Windows App SDK runtime dependencies and the Hydrogen backend into temporary folders at launch. macOS produces the standard `.app` bundle with AppKit as the direct entry executable (no launcher), but it currently carries separate runtime libraries and a compiled Hydrogen backend. Windows and macOS changes need CI verification. **Single-process event dispatch is not yet implemented on any platform.**
