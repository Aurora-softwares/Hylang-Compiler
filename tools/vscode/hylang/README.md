# Hylang VS Code Assets

This folder contains the light editor-support assets for the current Hylang bootstrap:

- syntax highlighting for `.hy` and `.hyproj`
- snippets for common Hylang scaffolds
- task templates for `hy check`, `hy fmt`, and `hy test`
- a launch template for `hy run`
- a small extension entrypoint that starts `hy lsp`
- a Node wrapper that turns `hy check --json` output into VS Code problem-matcher lines as a fallback task path

Recommended workflow:

1. Copy `templates/tasks.json`, `templates/launch.json`, and `templates/settings.json` into your workspace `.vscode/` folder.
2. Open the repo root as your VS Code workspace so the task template can find `tools/vscode/hylang/bin/hy-check-json.js`.
3. Make sure `hy` is on your `PATH`, set `HYLANG_BIN`, or configure `hylang.hyPath`.
4. The extension starts `hy lsp` for diagnostics, symbols, hover, and formatting. The check task remains useful in CI-style editor workflows.

This is intentionally a light integration layer, not a full semantic language server with completion or go-to-definition.
