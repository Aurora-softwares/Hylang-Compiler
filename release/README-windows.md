# Hydrogen for Windows x64

This archive contains the self-hosted native Hydrogen compiler. Extract the
archive into a dedicated directory and add its `bin` directory to your user
`PATH`. The `hy.cmd` launcher passes compiler commands to `libexec/hy-core.exe`
and lifecycle commands to `libexec/hy-maintenance.ps1`.

Use `hy --version`, `hy update-check`, `hy update`, and `hy uninstall` from a
new terminal. The official website installer places the release under
`%LOCALAPPDATA%\Hydrogen` and adds its `bin` directory to the user `PATH`.
The lifecycle assistant updates or removes only a manifest-bearing dedicated
installation. Unknown installation ownership fails safely.

`SHA256SUMS` covers the installed files and the adjacent `.zip.sha256` covers
the full archive. An updater also checks the GitHub release asset digest.
