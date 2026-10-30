#!/usr/bin/env python3
"""Run a real OS renderer and compare its screenshots with reviewed baselines."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[2]


def compare_images(actual, expected, difference):
    with Image.open(actual) as source:
        image = source.convert("RGB")
    if min(image.size) < 100 or max(ImageStat.Stat(image).stddev) < 5:
        raise AssertionError(f"Blank or invalid native screenshot: {actual}")
    with Image.open(expected) as source:
        baseline = source.convert("RGB")
    if image.size != baseline.size:
        raise AssertionError(f"Screenshot size changed: {actual.name}: {image.size} != {baseline.size}")
    # Native font rasterization and small OS patch differences are tolerated;
    # moved panels, missing controls, theme changes and blank views are not.
    small = image.resize((224, 180), Image.Resampling.LANCZOS)
    reference = baseline.resize(small.size, Image.Resampling.LANCZOS)
    delta = ImageChops.difference(small, reference)
    mean = sum(ImageStat.Stat(delta).mean) / (3 * 255)
    changed = sum(max(pixel) > 35 for pixel in delta.getdata()) / (224 * 180)
    ImageChops.difference(image, baseline).save(difference)
    if mean > 0.035 or changed > 0.12:
        raise AssertionError(f"Visual regression in {actual.name}: mean={mean:.4f}, changed={changed:.1%}; see {difference}")
    return {"mean_difference": mean, "changed_fraction": changed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True, choices=["macos", "linux", "windows"])
    parser.add_argument("--driver", required=True, type=Path)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--artifacts", required=True, type=Path)
    args = parser.parse_args()
    artifacts = args.artifacts.resolve(); artifacts.mkdir(parents=True, exist_ok=True)
    sample = ROOT / "samples/ui_studio"
    try:
        if args.platform == "windows":
            work = artifacts / "application"; work.mkdir(exist_ok=True)
            backend = work / "backend.exe"
            build = subprocess.run([str(args.compiler.resolve()), "build", str(sample / "Studio.hyproj"), "-o", str(backend), "--ui-backend", "--hide-progress", "--hide-log", "--hide-spinner"], capture_output=True, text=True, timeout=180)
            (artifacts / "backend-build.log").write_text(build.stdout + build.stderr, encoding="utf-8")
            if build.returncode:
                raise AssertionError("Windows sample backend failed to compile; see backend-build.log")
            shutil.copytree(sample / "assets", work / "assets", dirs_exist_ok=True)
            document = work / "Studio.hyui"
            document.write_text((sample / "Studio.hyui").read_text().replace('theme="system"', 'theme="light"'), encoding="utf-8")
            command = [str(args.driver.resolve()), "--backend", str(backend), "--document", str(document), "--ui-test", str(artifacts)]
        else:
            command = [str(args.driver.resolve()), str(sample / "Studio.hyui"), str(args.compiler.resolve()), str(artifacts)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=240, env=dict(os.environ, GSK_RENDERER="cairo"))
        (artifacts / "native-test.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        if result.returncode:
            raise AssertionError(f"{args.platform} native interaction/layout tests failed ({result.returncode}); see native-test.log")
        report = json.loads((artifacts / "report.json").read_text())
        required = {f"{page}-{width}.png" for page in ["workspace", "gallery"] for width in [1120, 800, 360]} | {"dialog-confirm.png", "workspace-bottom.png", "gallery-bottom.png"}
        if not report.get("passed") or set(report.get("screenshots", [])) != required or len(report["screenshots"]) != len(required):
            raise AssertionError("Native test did not complete all required captures")
        differences = artifacts / "diffs"; differences.mkdir(exist_ok=True)
        metrics = {}; failures = []
        for name in report["screenshots"]:
            actual = artifacts / name
            with Image.open(actual) as source:
                rgba = source.convert("RGBA")
                if name != "dialog-confirm.png":
                    transparent = sum(count for alpha, count in enumerate(rgba.getchannel("A").histogram()) if alpha < 128)
                    if transparent > rgba.width * rgba.height * 0.02:
                        raise AssertionError(f"Native screenshot is clipped or unrendered: {name}")
                Image.alpha_composite(Image.new("RGBA", rgba.size, "white"), rgba).convert("RGB").save(actual)
            expected = ROOT / "tests/ui/golden" / args.platform / name
            if not expected.is_file():
                failures.append(f"Missing reviewed baseline: {expected}; actual screenshot is in {artifacts}")
                continue
            try:
                metrics[name] = compare_images(artifacts / name, expected, differences / name)
            except AssertionError as error:
                failures.append(str(error))
        (artifacts / "visual-results.json").write_text(json.dumps({"platform": args.platform, "metrics": metrics, "failures": failures}, indent=2))
        if failures:
            raise AssertionError("\n".join(failures))
        print(f"{args.platform}: native interactions, layout and {len(metrics)} reviewed screenshots passed")
    except Exception as error:
        (artifacts / "failure.txt").write_text(str(error), encoding="utf-8")
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
