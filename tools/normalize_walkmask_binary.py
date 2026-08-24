"""Normalize the active walkmask without changing runtime walkability.

The game treats RGB values above 90 percent as walkable. This converts that
same classification to the documented strict black/white asset contract.
"""
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MASK_PATH = ROOT / "assets/generated/warehouse-layout-final-walkmask.png"


def main() -> None:
    source = Image.open(MASK_PATH).convert("RGB")
    luminance = source.convert("L")
    binary = luminance.point(lambda value: 255 if value > 229 else 0, mode="L")
    alpha = Image.new("L", binary.size, 255)
    Image.merge("RGBA", (binary, binary, binary, alpha)).save(MASK_PATH)
    values = set(binary.getdata())
    if values != {0, 255}:
        raise SystemExit(f"walkmask normalization failed: {sorted(values)}")
    print(f"normalized {MASK_PATH}")


if __name__ == "__main__":
    main()
