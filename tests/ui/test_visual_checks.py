"""Prove that the visual check rejects blank, resized and displaced content."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from PIL import Image, ImageDraw

spec = importlib.util.spec_from_file_location("ui_ci", Path(__file__).parents[2] / "tools/hyui/ui_ci.py")
ui_ci = importlib.util.module_from_spec(spec); spec.loader.exec_module(ui_ci)


class VisualChecks(unittest.TestCase):
    def test_rejects_actual_regressions_and_accepts_small_raster_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            reference = Image.new("RGB", (600, 400), "white")
            draw = ImageDraw.Draw(reference)
            draw.rectangle((30, 40, 280, 350), fill="#174580")
            draw.rectangle((310, 40, 570, 350), fill="#69aadd")
            reference.save(work / "expected.png")
            slightly_different = reference.copy(); ImageDraw.Draw(slightly_different).point((80, 80), fill="white")
            slightly_different.save(work / "actual.png")
            ui_ci.compare_images(work / "actual.png", work / "expected.png", work / "difference.png")
            for broken in [Image.new("RGB", (600, 400), "white"), reference.resize((550, 400)), ImageChops.offset(reference, 90, 0)]:
                broken.save(work / "actual.png")
                with self.assertRaises(AssertionError):
                    ui_ci.compare_images(work / "actual.png", work / "expected.png", work / "difference.png")


from PIL import ImageChops
if __name__ == "__main__": unittest.main()
