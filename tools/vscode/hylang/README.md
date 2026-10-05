# Hylang VS Code Assets

This folder contains editor support for the C++ SDK CLI (`hy`). The native Hydrogen CLI does not provide the required `lsp`, `fmt`, or JSON-check commands.

- syntax highlighting for `.hy` and `.hyproj`
- snippets for common Hylang scaffolds
- task templates for `hy check`, `hy fmt`, and `hy test`
- a launch template for `hy run`
- a small extension entrypoint that starts `hy lsp`
- a Node wrapper that turns `hy check --json` output into VS Code problem-matcher lines as a fallback task path

To load the extension in a VS Code development host, run from the compiler repository root:

```bash
code --extensionDevelopmentPath="$PWD/tools/vscode/hylang" "$PWD"
```

To configure a compiler checkout:

1. Copy `templates/tasks.json`, `templates/launch.json`, and `templates/settings.json` into your workspace `.vscode/` folder.
2. Open the repo root as your VS Code workspace so the task template can find `tools/vscode/hylang/bin/hy-check-json.js`.
3. Put `hy` on your `PATH` for the format/test/run templates, or edit their commands to point to `build/hy`. The check wrapper uses `HYLANG_BIN`, then the repository's `build/hy`, then `PATH`. The LSP launcher uses `HYLANG_BIN` or `hylang.hyPath`; that setting does not change task commands.
4. Use the check task for diagnostics and the format task to format sources. The extension entrypoint starts `hy lsp`, but does not yet connect VS Code language providers to its JSON-RPC stream.

The `hy lsp` server supports diagnostics, symbols, hover, and formatting for a client that implements its protocol. The included extension currently supplies highlighting/snippets and starts the process; it is not a complete LSP client. The settings template expresses format-on-save intent, but the extension does not yet register a formatter, so use `hy fmt` or the task. Completion, go-to-definition, references, rename, semantic tokens, and full workspace indexing are not implemented.
