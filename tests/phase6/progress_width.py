#!/usr/bin/env python3
"""Check interactive compiler progress at several PTY widths."""

import fcntl
import os
import pathlib
import pty
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time


def capture(command: list[str], project: pathlib.Path, output: pathlib.Path, width: int) -> str:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, width, 0, 0))
    process = subprocess.Popen(
        [*command, "build", str(project), "-o", str(output)],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env={**os.environ, "TERM": "xterm"},
    )
    os.close(slave)
    chunks = []
    deadline = time.monotonic() + 60
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break  # A Linux PTY reports EIO after the slave closes.
                if not chunk:
                    break
                chunks.append(chunk)
            if process.poll() is not None and not ready:
                break
        else:
            process.kill()
            raise AssertionError(f"build timed out at {width} columns")
    finally:
        os.close(master)
    text = b"".join(chunks).decode("utf-8")
    if process.wait() != 0:
        raise AssertionError(f"build failed at {width} columns:\n{text}")
    return text


def check(text: str, width: int) -> None:
    segments = re.split(r"[\r\n]", text)
    progress = []
    for segment in segments:
        line = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", segment)
        if line.startswith("Building ") or line.startswith("100% ") or \
           line.startswith("[") or (line and "\u2800" <= line[0] <= "\u28ff") or \
           re.match(r"^\d+% \| ", line):
            progress.append(line)
    if len(progress) < 3:
        raise AssertionError(f"missing interactive progress at {width} columns:\n{text}")
    for line in progress:
        if len(line.encode("utf-8")) > width - 1:
            raise AssertionError(f"progress exceeds {width} columns: {line!r}")
    if width == 40 and not any("..." in line for line in progress):
        raise AssertionError("long progress lines were not abbreviated")


def main() -> None:
    command = [sys.argv[1]]
    if len(sys.argv) > 2:
        command += ["run", sys.argv[2], "--"]
    for prefix, widths in (("hydrogen-progress-width-long-project-name-", (12, 40, 80)),
                           ("hhhhhhh😀longproject-", (40,))):
        with tempfile.TemporaryDirectory(prefix=prefix) as folder:
            directory = pathlib.Path(folder)
            (directory / "Program.hy").write_text(
                'public class Program { public static int Main(string[] args) { '
                'System.Console.WriteLine("ok"); return 0; } }\n'
            )
            project = directory / "LongProgressProject.hyproj"
            project.write_text('format = 2\nname = "LongProgressProject"\ntype = "exe"\n'
                               'sources = ["Program.hy"]\n')
            for width in widths:
                check(capture(command, project, directory / f"output-{width}", width), width)


if __name__ == "__main__":
    main()
