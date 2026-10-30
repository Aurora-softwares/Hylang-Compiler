"""Exercise the real Hydrogen compiler, XML host, and demo event handlers."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

host, compiler, root = map(lambda p: Path(p).resolve(), sys.argv[1:4])
if sys.platform == "linux" and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
    print("Native GTK integration requires a display; use xvfb-run in CI")
    sys.exit(77)
env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", GSK_RENDERER="cairo")


def run(*args, cwd=None, success=True):
    result = subprocess.run(list(map(str, args)), cwd=cwd, env=env,
                            capture_output=True, text=True, timeout=120)
    if (result.returncode == 0) != success:
        raise AssertionError(f"{args}: {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result


with tempfile.TemporaryDirectory(prefix="hydrogen ui ' ") as temporary:
    work = Path(temporary)
    app = work / ("application.exe" if os.name == "nt" else "application")
    sample = root / "samples/ui_studio"
    run(compiler, "build", sample / "Studio.hyproj", "-o", app, "--ui-backend")
    app.chmod(app.stat().st_mode | 0o100)
    xml = (sample / "Studio.hyui").read_text()
    # Keep Build deterministic; the timer's callback is tested separately below.
    (work / "Studio.hyui").write_text(xml.replace('interval="350"', 'interval="30000"'))
    run(host, "--document", work / "Studio.hyui", "--validate")

    def state(event=None, width=1100):
        args = [host, "--backend", app, "--size", f"{width}x740",
                "--state-output", work / "state.json", "--screenshot", work / "window.png"]
        if event:
            args += ["--event", event]
        run(*args)
        image = (work / "window.png").read_bytes()
        assert image.startswith(b"\x89PNG\r\n\x1a\n")
        actual_width, actual_height = struct.unpack(">II", image[16:24])
        assert 0 < actual_width <= width and actual_height <= 740
        return json.loads((work / "state.json").read_text())

    initial = state(width=360)
    assert initial["projectName.text"] == "Aurora Notes"
    preview = state("Preview:projectName")
    assert "Optimisation: 70%" in preview["summary.text"]
    started = state("Build:build")
    assert started["build.enabled"] is False
    assert started["activity.running"] is True
    assert started["buildTimer.running"] is True
    tick = state("Tick:buildTimer")
    assert tick["progress.value"] == 10
    stopped = state("Cancel:cancel")
    assert stopped["activity.running"] is False
    assert stopped["buildTimer.running"] is False
    assert stopped["build.enabled"] is True
    saved = state("Save:save")
    assert "Saved application plan" in saved["status.text"]
    assert "A calm place for everyday ideas." in (work / "hydrogen-build-plan.txt").read_text()

    (work / "Studio.hyui").write_text(xml.replace('id="progress" value="0"', 'id="progress" value="90"'))
    completed = state("Tick:buildTimer")
    assert completed["progress.value"] == 100
    assert completed["save.enabled"] is True
    assert completed["buildTimer.running"] is False

    (work / "Studio.hyui").write_text(xml.replace('id="projectName" text="Aurora Notes"', 'id="projectName" text=""'))
    invalid = state("Build:build")
    assert "Give your project a name" in invalid["status.text"]
    assert invalid["buildTimer.running"] is False

    # A single .hy entry point uses the host's embedded Hydrogen.UI library.
    run(host, "--source", sample / "Program.hy", "--compiler", compiler,
        "--size", "360x740", "--state-output", work / "single.json")
    assert json.loads((work / "single.json").read_text())["projectName.text"] == "Aurora Notes"
    (work / "bad.hyui").write_text('<Window version="1"><Unknown/></Window>')
    run(host, "--document", work / "bad.hyui", "--validate", success=False)

print("HYUI compiler integration passed: startup, input snapshot, progress, completion, cancel, save, validation, single-file launch")
