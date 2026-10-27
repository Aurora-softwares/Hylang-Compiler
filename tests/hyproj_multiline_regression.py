#!/usr/bin/env python3
"""Integration regressions for .hyproj parsing (bootstrap SDK or self-hosted CLI).

Usage: python3 tests/hyproj_multiline_regression.py /path/to/hy [--selfhost] --repo .
"""
import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ARGS = None
ENGINE = None
TMP = None


def run(*argv, timeout=150):
    return subprocess.run([str(a) for a in argv], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=timeout)


def require_ok(proc, what):
    if proc.returncode:
        raise AssertionError(f"{what} returned {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")


def make_executable(path):
    # The self-hosted writer creates ELF files without their execute bit.
    # Existing native integration tests also set it before launching output.
    if ARGS.selfhost:
        path.chmod(path.stat().st_mode | 0o111)


def make_app(manifest):
    base = TMP / 'app'
    base.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ARGS.repo / 'tests/projects/app/Program.hy', base / 'Program.hy')
    lib = TMP / 'mathlib'
    lib.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ARGS.repo / 'tests/projects/mathlib/Math.hy', lib / 'Math.hy')
    (lib / 'Math.hyproj').write_text('format = 2\nname = "MathLib"\ntype = "lib"\nsources = ["Math.hy"]\nproject_references = []\n')
    project = base / 'App.hyproj'
    project.write_text(manifest)
    return project


def app_manifest(sources, references):
    return 'format = 2\nname = "DemoApp"\ntype = "exe"\n' + sources + '\n' + references + '\n'


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.subdir = tempfile.TemporaryDirectory(prefix='hyproj-case-', dir=TMP)
        self.saved = globals()['TMP']
        globals()['TMP'] = pathlib.Path(self.subdir.name)

    def tearDown(self):
        globals()['TMP'] = self.saved
        self.subdir.cleanup()

    def build_and_check_app(self, source_syntax, refs_syntax):
        manifest = app_manifest(source_syntax, refs_syntax)
        project = make_app(manifest)
        binary = TMP / 'app' / 'out'
        result = run(ENGINE, 'build', project, '-o', binary)
        require_ok(result, 'compiling app with project references')
        self.assertTrue(binary.is_file(), 'no output executable created')
        make_executable(binary)
        execution = run(binary)
        require_ok(execution, 'running compiled application')
        self.assertIn('Hello from MathUtil', execution.stdout)
        self.assertIn('7', execution.stdout)

    def test_one_line_compatibility(self):
        self.build_and_check_app('sources = ["Program.hy"]',
                                 'project_references = ["../mathlib/Math.hyproj"]')

    def test_multiline_arrays(self):
        self.build_and_check_app('sources = [\n    "Program.hy"\n]',
                                 'project_references = [\n    "../mathlib/Math.hyproj"\n]')

    def test_multiline_arrays_with_blank_line_and_trailing_comma(self):
        self.build_and_check_app('sources = [\n\n    "Program.hy",\n]',
                                 'project_references = [\n    "../mathlib/Math.hyproj",\n\n]')

    def test_unterminated_array_rejected(self):
        project = make_app(app_manifest('sources = ["Program.hy"]',
                            'project_references = [\n    "../mathlib/Math.hyproj",\n'))
        binary = TMP / 'invalid-out'
        result = run(ENGINE, 'build', project, '-o', binary)
        self.assertNotEqual(result.returncode, 0, 'unterminated array accepted')
        self.assertRegex(result.stdout + result.stderr,
                         r'(?i)(unterminated|invalid|expected).*array|(?i:invalid.*hyproj)')

    def test_multiline_description_preserved(self):
        base = TMP / 'probe'
        base.mkdir()
        shutil.copy2(ARGS.repo / 'samples/self_hosting/Hydrogen.Compiler.Core/HyprojManifest.hy',
                     base / 'HyprojManifest.hy')
        (base / 'Probe.hy').write_text('''using Hydrogen.Compiler.Core;

namespace Probe {
    public class Program {
        public static int Main(string[] args) {
            HyprojManifest m = HyprojManifest.Load(args[0]);
            System.Console.WriteLine(m.Description());
            return 0;
        }
    }
}
''')
        probe = base / 'Probe.hyproj'
        probe.write_text('''format = 2
name = "Probe"
type = "exe"
sources = ["Probe.hy", "HyprojManifest.hy"]
project_references = []
''')
        description = TMP / 'description.hyproj'
        description.write_text('''format = 2
name = "DescriptionTest"
type = "lib"
sources = []
project_references = []

[package]
id = "DescriptionTest"
description = |
    First line.

    Second line.
''')
        binary = base / 'probe-out'
        build = run(ENGINE, 'build', probe, '-o', binary)
        require_ok(build, 'building description probe')
        make_executable(binary)
        outcome = run(binary, description)
        require_ok(outcome, 'running description probe')
        self.assertEqual(outcome.stdout.replace('\r\n', '\n'),
                         'First line.\n\nSecond line.\n')


def main():
    global ARGS, ENGINE, TMP
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=pathlib.Path)
    parser.add_argument('--repo', required=True, type=pathlib.Path)
    parser.add_argument('--selfhost', action='store_true')
    ARGS = parser.parse_args()
    ARGS.repo = ARGS.repo.resolve()
    with tempfile.TemporaryDirectory(prefix='hyproj-regression-') as directory:
        TMP = pathlib.Path(directory)
        ENGINE = ARGS.binary.resolve()
        if ARGS.selfhost:
            candidate = TMP / 'hydrogen-stage1'
            project = (ARGS.repo / 'samples/self_hosting/Hydrogen.Compiler.Cli/'
                       'Hydrogen.Compiler.Cli.hyproj')
            build = run(ENGINE, 'build', project, '-o', candidate, timeout=240)
            require_ok(build, 'building self-hosted Hydrogen CLI')
            ENGINE = candidate
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ManifestTests)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
