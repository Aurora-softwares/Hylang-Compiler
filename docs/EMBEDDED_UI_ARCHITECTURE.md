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
- 🔴 Make the default `hy build <ui.hyproj>` generate and launch a full native application without any auxiliary host executable. This is the requested next release gate.
- 🔴 Implement the full native `.hyui` schema in Hydrogen so compilation validates exactly what runtime accepts.
- [ ] Replace process-based `Bridge` event delivery with **in-process** calls into the compiled Hydrogen application.
- [ ] Define target-specific UI runtime ABI for Linux GTK4/libadwaita, Windows WinUI 3, and macOS AppKit. Preserve OS theme and controls.
- [ ] Extend each target compiler/linker to link the appropriate UI entry point and runtime into the generated app rather than generating a launcher/backend pair.
- [ ] Embed or package required document/assets with the app; keep safe path and size checks.
- [ ] Remove `hyui-native`/`hyui-launcher` dependency from Linux and desktop packaging paths only after parity tests pass.
- [ ] Build the sample via each Stage 1–3 binary; assert one runnable app entry point, one process, correct event dispatch, and visual fidelity.
- [ ] Run bootstrap reproducibility checks and native visual regression tests on supported hosts.

## Acceptance criteria for the final implementation

1. `hydrogen-stageN build samples/ui_studio/Studio.hyproj -o build/ui_studio` succeeds on a clean supported host **without** the `hyui-native` or `hyui-launcher` executable, for N = 1, 2, 3.
2. On Linux, `build/ui_studio` is the program itself; no `build/ui_studio.runtime/hyui` or `__hyui_backend` executable.
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
```

**Current limitation:** Production UI app builds still require the separate renderer and launcher. Compiler-only `--ui-backend` builds work without a host but print HYUI protocol commands rather than opening a window. The final single-process graphical application criterion is **not yet met**.
