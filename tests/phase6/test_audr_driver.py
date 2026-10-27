#!/usr/bin/env python3
"""Compiler contract test for the Australis AUDR v1 kernel-module image."""

import argparse
import pathlib
import struct
import subprocess
import tempfile
import zlib


def run(compiler, *args, success=True):
    result = subprocess.run([str(compiler), *map(str, args)], capture_output=True, text=True, timeout=60)
    if (result.returncode == 0) != success:
        raise AssertionError(f"hy {args} returned {result.returncode}: {result.stdout}{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=pathlib.Path)
    parser.add_argument("source", type=pathlib.Path)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    sample = args.source.resolve() / "samples/australis_driver/ExampleDriver.hyproj"

    with tempfile.TemporaryDirectory(prefix="audr-test-") as tmp:
        root = pathlib.Path(tmp)
        project_dir = root / "Nested" / "Driver"
        run(compiler, "new", "driver", project_dir)
        project = project_dir / "Driver.hyproj"
        assert project.exists() and (project_dir / "DriverMain.hy").exists()
        run(compiler, "check", project)
        collection = root / "Drivers.hyproj"
        collection.write_text('format = 2\nname = "Drivers"\ntype = "collection"\n'
                              'project_references = ["Nested/Driver/Driver.hyproj"]\n')
        run(compiler, "check", collection)
        collection_output = root / "collection-output"
        collection_output.mkdir()
        run(compiler, "build", collection, "-o", collection_output,
            "--hide-progress", "--hide-spinner", "--hide-log")
        assert (collection_output / "Driver.driver").read_bytes().startswith(b"AUDR")

        sample_image = root / "Sample.driver"
        run(compiler, "check", sample)
        run(compiler, "build", sample, "-o", sample_image, "--hide-progress", "--hide-spinner", "--hide-log")
        image = sample_image.read_bytes()
        assert len(image) >= 25 and image[:8] == b"AUDR\x01\x01\0\0"
        code_length, entry, checksum, reserved = struct.unpack_from("<IIII", image, 8)
        assert 1 <= code_length <= 65536
        assert len(image) == 24 + code_length and entry == 0 and reserved == 0
        assert checksum == zlib.crc32(image[24:])
        assert image[24:35] == bytes.fromhex("57e8050000004883c408c3")
        second = root / "Second.driver"
        run(compiler, "build", sample, "-o", second, "--hide-progress", "--hide-spinner", "--hide-log")
        assert second.read_bytes() == image

        matched = root / "Matched.hyproj"
        matched_source = root / "Matched.hy"
        matched_source.write_text((sample.parent / "DriverMain.hy").read_text())
        matched.write_text('format = 2\nname = "Matched"\ntype = "driver"\n'
                           'sources = ["Matched.hy"]\n\n[driver]\nabi = 2\n'
                           'match = "pci"\nvendor = 65535\ndevice = 65535\n'
                           'class = 12\nsubclass = 3\ninterface = 48\n')
        run(compiler, "check", matched)
        matched_image = root / "Matched.driver"
        run(compiler, "build", matched, "-o", matched_image,
            "--hide-progress", "--hide-spinner", "--hide-log")
        v2 = matched_image.read_bytes()
        assert v2[:8] == b"AUDR\x02\x02\0\0"
        assert struct.unpack_from("<IIIIII", v2, 24) == (1, 65535, 65535, 12, 3, 48)
        assert len(v2) == 48 + struct.unpack_from("<I", v2, 8)[0]
        assert struct.unpack_from("<I", v2, 16)[0] == zlib.crc32(v2[24:])
        usb = root / "Usb.hyproj"
        usb.write_text(matched.read_text().replace('match = "pci"', 'match = "usb"'))
        usb_image = root / "Usb.driver"
        run(compiler, "check", usb)
        run(compiler, "build", usb, "-o", usb_image,
            "--hide-progress", "--hide-spinner", "--hide-log")
        assert struct.unpack_from("<I", usb_image.read_bytes(), 24)[0] == 2

        matched.write_text(matched.read_text().replace("interface = 48", "interface = 999"))
        run(compiler, "check", matched, success=False)
        run(compiler, "build", matched, "-o", matched_image,
            "--hide-progress", success=False)
        assert matched_image.read_bytes() == v2
        matched.write_text(matched.read_text().replace("interface = 999",
                                                       "interface = " + "9" * 80))
        run(compiler, "check", matched, success=False)

        bad_source = root / "Bad.hy"
        bad_project = root / "Bad.hyproj"
        bad_output = root / "Bad.driver"
        bad_source.write_text("public class DriverMain { public static int Run(long context) { System.Console.WriteLine(\"unsupported\"); return 0; } }\n")
        bad_project.write_text('format = 2\nname = "Bad"\ntype = "driver"\nsources = ["Bad.hy"]\n')
        bad_output.write_bytes(b"preserved")
        run(compiler, "check", bad_project, success=False)
        run(compiler, "build", bad_project, "-o", bad_output, "--hide-progress", success=False)
        assert bad_output.read_bytes() == b"preserved"
        bad_source.write_text("public class WrongEntry { public static int Run(long context) { return 0; } }\n")
        run(compiler, "check", bad_project, success=False)
        run(compiler, "build", bad_project, "-o", bad_output, "--hide-progress", success=False)
        assert bad_output.read_bytes() == b"preserved"


if __name__ == "__main__":
    main()
