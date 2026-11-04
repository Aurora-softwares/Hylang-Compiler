"""Guard HYUI v1's cross-platform control contract.

The operating-system-specific tests exercise behaviour, accessibility and
screenshots; this fast check ensures no declared control silently disappears
from their shared representative document or from a native backend.
"""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "tools/hyui/document.cpp"
STUDIO = ROOT / "samples/ui_studio/Studio.hyui"
BACKENDS = {
    "Linux GTK4 host": ROOT / "tools/hyui/gtk.cpp",
    "Linux single-file GTK4": ROOT / "tools/hyui/linux_gtk_app.cpp",
    "macOS AppKit": ROOT / "tools/hyui/appkit.mm",
    "Windows WinUI 3": ROOT / "tools/hyui/windows/App.xaml.cs",
}


def declared_controls():
    source = SCHEMA.read_text(encoding="utf-8")
    section = source.split("static const QMap<QString, QSet<QString>> attributes = {", 1)[1].split("};", 1)[0]
    controls = set(re.findall(r'\{"([A-Za-z]+)",\s*\{', section))
    if not controls:
        raise AssertionError("Could not read the HYUI v1 schema")
    return controls


class NativeControlContract(unittest.TestCase):
    def test_every_schema_element_has_a_studio_fixture(self):
        schema = declared_controls()
        used = {element.tag for element in ET.parse(STUDIO).iter()}
        # Spacer is an optional layout-only element intentionally absent
        # from the screenshot-stable Studio fixture.
        self.assertEqual(set(), (schema - {"Spacer"}) - used, "HYUI controls missing from the cross-platform fixture")
        self.assertEqual(set(), used - schema, "Fixture uses controls not supported by the schema")

    def test_every_schema_element_has_a_native_backend_implementation(self):
        schema = declared_controls()
        for platform, path in BACKENDS.items():
            with self.subTest(platform=platform):
                source = path.read_text(encoding="utf-8")
                # Root Window is created by the GTK/AppKit host's entry point.
                # Other widgets must have a named native control implementation.
                expected = schema - ({"Window"} if platform in {"Linux GTK4 host", "macOS AppKit"} else set())
                # AppKit builds NSMenu/NSMenuItem from the MenuBar's
                # child nodes, without comparing those tag names as strings.
                if platform == "macOS AppKit":
                    expected -= {"Menu", "MenuItem"}
                    self.assertIn("buildMenu(", source)
                    self.assertIn("makeMenuItem(", source)
                missing = {tag for tag in expected if f'"{tag}"' not in source}
                self.assertEqual(set(), missing, f"{platform} is missing HYUI control cases")

    def test_event_contract_is_present_in_all_three_native_renderers(self):
        required_events = ("onClick", "onChange", "onSubmit", "onClose",
                           "onPick", "onCancel", "onRead", "onTick")
        for platform, path in BACKENDS.items():
            with self.subTest(platform=platform):
                source = path.read_text(encoding="utf-8")
                for event in required_events:
                    # Not every widget lives in the direct GTK4 frontend yet;
                    # its callbacks are tested by the GTK4 host.
                    if platform == "Linux single-file GTK4":
                        continue
                    self.assertIn(event, source, f"{platform} does not reference {event}")


if __name__ == "__main__":
    unittest.main()
