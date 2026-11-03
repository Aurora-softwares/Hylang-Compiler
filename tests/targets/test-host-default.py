#!/usr/bin/env python3
"""Verify portable Hydrogen builds select the host OS and explicit targets win.

Usage: python3 tests/targets/test-host-default.py <hydrogen-stage1>
No third-party Python packages or native UI SDK required.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

MAGIC = {"linux": b"\x7fELF", "windows": b"MZ", "macos": b"\xcf\xfa\xed\xfe"}


def run(compiler: pathlib.Path, args: list[str]) -> None:
    command = [str(compiler), *args]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise AssertionError(
            f"Command failed ({result.returncode}): {command}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def check_magic(path: pathlib.Path, platform: str) -> None:
    if not path.is_file():
        raise AssertionError(f"Missing {platform} output: {path}")
    actual = path.read_bytes()[:4]
    if not actual.startswith(MAGIC[platform]):
        raise AssertionError(
            f"Expected {platform} magic {MAGIC[platform].hex()} in {path}; "
            f"got {actual.hex()}"
        )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: test-host-default.py <hydrogen-compiler>")
    compiler = pathlib.Path(sys.argv[1]).resolve(strict=True)
    host = "windows" if sys.platform == "win32" else (
        "macos" if sys.platform == "darwin" else "linux"
    )
    with tempfile.TemporaryDirectory(prefix="hydrogen-host-target-") as directory:
        root = pathlib.Path(directory)
        source = root / "Program.hy"
        source.write_text(
            'public class Program {\n'
            '    public static void Main(string[] args) {\n'
            '        System.Console.WriteLine("Host target works");\n'
            '    }\n'
            '}\n',
            encoding="utf-8",
        )
        project = root / "Portable.hyproj"
        project.write_text(
            'format = 2\nname = "Portable"\ntype = "exe"\n'
            'sources = ["Program.hy"]\n',
            encoding="utf-8",
        )
        host_suffix = ".exe" if host == "windows" else ""
        for action in ("build", "compile"):
            destination = root / (action + "-default" + host_suffix)
            arguments = [str(project if action == "build" else source),
                         "-o", str(destination)]
            run(compiler, [action, *arguments])
            check_magic(destination, host)
            print(f"{action}: host {host} selected correctly")

        # Cross-compilation remains available explicitly, even if the host
        # differs from the requested output format.
        for requested in ("linux", "windows", "macos"):
            output = root / ("explicit-" + requested)
            run(compiler, ["build", str(project), "--target", requested,
                           "-o", str(output)])
            check_magic(output, requested)
        for requested in ("linux-x64", "windows-x64", "macos-x64"):
            platform = requested.removesuffix("-x64")
            output = root / ("compile-" + platform)
            run(compiler, ["compile", str(source), "--target", requested,
                           "-o", str(output)])
            check_magic(output, platform)
        print(f"Hydrogen host target and explicit override checks passed on {host}.")


if __name__ == "__main__":
    main()
