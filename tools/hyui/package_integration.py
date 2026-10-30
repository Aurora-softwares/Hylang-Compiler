"""Real build -> relocate -> launch, without Hydrogen or source files at runtime."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

host, compiler, repo = map(lambda p: Path(p).resolve(), sys.argv[1:4])
if sys.platform != "linux" or not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
    print("Native GTK package integration requires a display (use xvfb-run in CI).")
    sys.exit(77)
env = dict(os.environ, HYUI_COMPILER=str(compiler),
           PATH=str(host.parent) + os.pathsep + os.environ.get("PATH", ""), GSK_RENDERER="cairo")


def run(*args, cwd=None, success=True, environment=env):
    result = subprocess.run(list(map(str, args)), env=environment, cwd=cwd,
                            capture_output=True, text=True, timeout=180)
    if (result.returncode == 0) != success:
        raise AssertionError(f"{args}: {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result


with tempfile.TemporaryDirectory(prefix="hydrogen native package ' ") as temporary:
    root = Path(temporary)
    source = root / "source"
    (source / "views").mkdir(parents=True)
    (source / "assets").mkdir()
    (source / "assets/message.txt").write_text("copied application resource")
    shutil.copy(repo / "samples/ui_studio/Studio.hyui", source / "views/main.hyui")
    shutil.copytree(repo / "samples/ui_studio/assets", source / "views/assets", dirs_exist_ok=True)
    shutil.copytree(repo / "samples/ui_studio/assets", source / "assets", dirs_exist_ok=True)
    project = source / "app.hyproj"
    project_text = ('format = 2\nname = "PackagedStudio"\ntype = "exe"\n'
                    'ui = "views/main.hyui"\nui_assets = ["assets", "views/assets"]\n'
                    f'sources = ["{repo / "samples/ui_studio/Program.hy"}"]\n'
                    f'project_references = ["{repo / "libraries/Hydrogen.UI/Hydrogen.UI.hyproj"}"]\n')
    project.write_text(project_text)
    output = root / "built/Studio"
    run(compiler, "build", project, "-o", output)
    assert output.read_bytes().startswith(b"\x7fELF") and os.access(output, os.X_OK)
    runtime = Path(str(output) + ".runtime")
    metadata = json.loads((runtime / "hyui-runtime.json").read_text())
    assert metadata["target"] == "linux-x64" and metadata["renderer"] == "gtk4"
    assert not (runtime / "lib/libgtk-4.so.1").exists(), "GTK must come from the OS"
    assert not list((runtime / "lib").glob("libglib*")), "GTK's support libraries must also track the OS"
    assert not list(runtime.rglob("libQt6Quick*")), "native packages must not deploy replica styles"
    assert (runtime / "app/assets/message.txt").read_text() == "copied application resource"

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    def preserved():
        assert hashlib.sha256(output.read_bytes()).hexdigest() == digest
        assert json.loads((runtime / "app/__hyui_app.json").read_text())["format"] == 1

    original_xml = (source / "views/main.hyui").read_text()
    (source / "views/main.hyui").write_text('<Window version="1"><Unknown/></Window>')
    run(compiler, "build", project, "-o", output, success=False)
    preserved()
    (source / "views/main.hyui").write_text(original_xml)
    project.write_text(project_text.replace('["assets"]', '["../outside"]'))
    run(compiler, "build", project, "-o", output, success=False)
    preserved()
    project.write_text(project_text)
    result = run(compiler, "build", project, "-o", output, "--target", "windows", success=False)
    assert "runtime" in result.stderr.lower()
    preserved()

    # Rebuilding replaces only owned package outputs and retains complete files.
    run(compiler, "build", project, "-o", output)
    preserved()
    relocated = root / "different place ' quoted"
    relocated.mkdir()
    shutil.move(output, relocated / "Studio")
    shutil.move(runtime, relocated / "Studio.runtime")
    shutil.rmtree(source)
    clean = dict(env, PATH="/nonexistent", QT_PLUGIN_PATH="/nonexistent", QML_IMPORT_PATH="/nonexistent")
    state = root / "state.json"
    screenshot = root / "native.png"
    run(relocated / "Studio", "--state-output", state, "--screenshot", screenshot, cwd="/", environment=clean)
    assert "Ready when you are" in json.loads(state.read_text())["status.text"]
    run(relocated / "Studio", "--event", "Preview:projectName", "--state-output", state, cwd="/", environment=clean)
    assert "Optimisation: 70%" in json.loads(state.read_text())["summary.text"]
    assert screenshot.read_bytes().startswith(b"\x89PNG")
    run(relocated / "Studio", "--screenshot", "relative-native.png", "--state-output", "relative-state.json",
        cwd=root, environment=clean)
    assert (root / "relative-native.png").read_bytes().startswith(b"\x89PNG")
    assert json.loads((root / "relative-state.json").read_text())["projectName.text"] == "Aurora Notes"
    run(relocated / "Studio", "--event", "Save:save", "--state-output", state,
        cwd="/", environment=clean)
    assert (relocated / "Studio.runtime/app/hydrogen-build-plan.txt").is_file()

print("Native UI package integration passed: build, target validation, failure preservation, rebuild, assets, relocation, compiler-free launch, callbacks, save, screenshot")
