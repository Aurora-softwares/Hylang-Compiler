"""End-to-end Stage 1 build -> native launcher -> live GTK app, without UI setup flags.

Run under a graphical session (e.g. xvfb-run in Linux CI).
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
compiler = Path(sys.argv[1]).resolve()
work = Path(sys.argv[2]).resolve()
work.mkdir(parents=True, exist_ok=True)
output = work / "Studio"
project = Path("samples/ui_studio/Studio.hyproj")
environment = os.environ.copy()
environment.pop("HYUI_COMPILER", None)
environment.pop("HYUI_RUNTIME_ROOT", None)

# Neither the compiler nor the native SDK should be on PATH. The CLI must
# locate the SDK and correctly pass the Stage 1 compiler to its packager.
environment["PATH"] = os.pathsep.join(
    item for item in environment.get("PATH", "").split(os.pathsep)
    if item and not Path(item).resolve().is_relative_to(ROOT)
)
if shutil.which("hyui", path=environment.get("PATH")) is not None:
    raise AssertionError("CI test must not find hyui through PATH")


def run(*command, cwd=ROOT):
    result = subprocess.run(
        [str(part) for part in command],
        cwd=cwd, env=environment, text=True, capture_output=True,
        timeout=240,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"Command failed ({result.returncode}): {command}\n"
            f"{result.stdout}\n{result.stderr}"
        )
    return result


assert compiler.is_file(), "Stage 1 compiler is missing"
assert (ROOT / "build-ui/hyui").is_file(), "HYUI host is missing"
build = run(compiler, "build", project, "-o", output)
assert "bundled UI and native desktop host" in build.stdout, build.stdout
runtime = Path(str(output) + ".runtime")
assert output.is_file() and os.access(output, os.X_OK), "native app launcher missing"
assert (runtime / "hyui").is_file(), "native host missing from package"
assert (runtime / "app/__hyui_backend").is_file(), "Hydrogen backend not embedded"
assert (runtime / "app/Studio.hyui").is_file(), "UI document not embedded"
assert (runtime / "app/assets/hydrogen.png").is_file(), "UI asset missing"
metadata = json.loads((runtime / "hyui-runtime.json").read_text())
assert metadata["target"] == "linux-x64" and metadata["renderer"] == "gtk4"

# Launch exactly the built executable, from a different working directory.
# The packaged app cannot depend on the compiler, project sources, or cwd.
state_file = work / "state.json"
screenshot = work / "studio.png"
run(output, "--state-output", state_file, "--screenshot", screenshot, cwd=work)
state = json.loads(state_file.read_text())
assert state["projectName.text"] == "Aurora Notes", state
assert "Ready when you are" in state["status.text"], state
assert screenshot.read_bytes().startswith(b"\\x89PNG\\r\\n\\x1a\\n")

# A UI event must reach Hydrogen and change the native window state.
run(output, "--event", "ShowControls:showControls", "--state-output",
    state_file, cwd=work)
assert json.loads(state_file.read_text())["pages.value"] == 1

print("Stage 1 automatic HYUI packaging passed: build, resources, GTK launch, event; no UI exports or PATH changes")
