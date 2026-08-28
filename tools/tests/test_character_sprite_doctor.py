from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from character_sprite_doctor import audit_strip  # noqa: E402
from install_character_assets import remove_connected_background  # noqa: E402


def frame(box=(64, 139, 448, 457), color=(205, 105, 45, 255)) -> Image.Image:
    image = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle(box, fill=color)
    return image


def strip(frames: list[Image.Image]) -> Image.Image:
    result = Image.new("RGBA", (512 * len(frames), 512), (0, 0, 0, 0))
    for index, item in enumerate(frames):
        result.alpha_composite(item, (index * 512, 0))
    return result


class CharacterSpriteDoctorTests(unittest.TestCase):
    def test_ferret_style_fragment_is_not_hidden_by_dominant_width(self) -> None:
        clean = frame()
        bad = clean.copy()
        ImageDraw.Draw(bad).rectangle((205, 94, 219, 109), fill=(235, 120, 35, 255))
        audit = audit_strip(strip([clean, clean, bad, clean]))
        codes = {issue.code for issue in audit.issues}
        self.assertIn("disconnected_components", codes)
        self.assertIn("top_bound_jitter", codes)
        self.assertIn("adjacent_scale_jump", codes)

    def test_substantial_horizontal_boundary_fragment_is_reported(self) -> None:
        contaminated = frame()
        ImageDraw.Draw(contaminated).rectangle((0, 210, 23, 233), fill=(225, 115, 45, 255))
        audit = audit_strip(strip([contaminated, contaminated]))
        self.assertIn("panel_boundary_fragment", {issue.code for issue in audit.issues})

    def test_backdrop_cleanup_preserves_small_neutral_edge_art(self) -> None:
        backdrop = Image.new("RGBA", (64, 48), (220, 220, 220, 255))
        ImageDraw.Draw(backdrop).rectangle((20, 8, 44, 44), fill=(90, 55, 30, 255))
        cleaned = remove_connected_background(backdrop)
        self.assertEqual(0, cleaned.getpixel((0, 0))[3])
        self.assertEqual(255, cleaned.getpixel((32, 24))[3])

        edge_art = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
        ImageDraw.Draw(edge_art).rectangle((0, 20, 2, 28), fill=(245, 245, 245, 255))
        preserved = remove_connected_background(edge_art)
        self.assertEqual(255, preserved.getpixel((1, 24))[3])


if __name__ == "__main__":
    unittest.main()
