# Hydrogen

This archive contains the self-hosted Hydrogen compiler for Linux x86-64.

## Install manually

Extract the release archive into a directory dedicated to Hydrogen and add its
`bin` directory to `PATH`:

```bash
export PATH="/path/to/hydrogen-alpha-0.0.1-linux-x86_64/bin:$PATH"
```

The archive includes the launcher (`bin/hy`), native compiler
(`libexec/hy-core`), lifecycle assistant (`libexec/hy-maintenance`), and a
strict `INSTALL-MANIFEST`. Keep them together. Do not copy just `bin/hy` into
`/usr/bin` or another package-owned directory. For a system-wide manual install,
use a dedicated directory such as `/opt/hydrogen/<version>` and a symlink to
`bin/hy`; removal will not remove the external symlink automatically.

```bash
hy check hello.hy
hy compile hello.hy -o hello
chmod +x hello
./hello
```

## Updates and removal

```bash
hy --version
hy update-check
hy update
hy update --force
hy uninstall
hy uninstall --force
hy remove   # alias of uninstall
```

The launcher checks whether APT/dpkg, RPM (DNF/YUM), Pacman or Homebrew owns
its installed executable and delegates to that manager. DNF/YUM use their
native update-check behaviour; APT displays installed/candidate versions from
its local metadata. The Pacman update path performs a system upgrade as well
as upgrading Hydrogen, rather than risking a partial system upgrade.

If the installation is manual, `update-check` queries GitHub Releases in the
current release channel (stable/alpha/beta/rc). `update` downloads the matching
Linux x86-64 archive and sidecar checksum, verifies them against GitHub's
release asset digest, validates archive contents and per-file hashes, and
replaces the dedicated installation directory with rollback on activation
failure. `--force` skips confirmation and can reinstall an up-to-date manual
release; it never disables integrity/ownership checks.

Manual updates require `bash`, `curl`, `jq`, `tar`, GNU `sha256sum`, and a
writable installation parent. The updater refuses unmanaged files under the
installation directory. User projects and settings outside the release directory
are never deleted. Uninstallation removes only manifest-listed release files.

**Important:** Published GitHub Releases must contain an archive named
`hydrogen-<tag>-linux-x86_64.tar.gz` and matching `.tar.gz.sha256` file;
GitHub must expose a SHA-256 `digest` for the archive asset. Release transport,
GitHub metadata and checksums provide integrity assurance, but they are not a
substitute for an independently signed release. Add release-signing keys before
requiring stronger supply-chain authenticity.

Bare manually compiled `hy` binaries from before this launcher was introduced
have no installation manifest. The updater intentionally will not attempt to
adopt, replace or remove those binaries automatically. Install a manifest-bearing
archive first.

## Other targets

```bash
hy compile uefi_hello.hy --target uefi-x64 -o BOOTX64.EFI
```

`BOOTX64.EFI` is firmware code, not a Linux executable. The UEFI target supports
ASCII-literal console output, screen clearing, one key wait, and EFI image
launch. Its early-kernel profile also supports a fixed boot-services exit,
memory/paging initialization, heap, framebuffer output, and halt sequence. It
does not provide a general UEFI runtime or standard library.

## Verify the compiler

`SHA256SUMS` contains checksums of the installed release files. The companion
`.tar.gz.sha256` file checks the complete archive download.

See the [documentation](https://github.com/Aurora-Softwares/Hylang-Docs) and
[issue tracker](https://github.com/Aurora-Softwares/Hylang-Compiler/issues).
