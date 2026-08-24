"""Add the selected warehouse's player-width office doorway to its binary mask."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
MASK_PATH = ROOT / "assets" / "generated" / "warehouse-walkmask.png"


def main() -> None:
    mask = Image.open(MASK_PATH).convert("L")
    if mask.size != (1492, 1054):
        raise ValueError(f"Unexpected walkmask size: {mask.size}")

    # Bridge the office floor to the main-floor component at the selected
    # office's right-side opening. The 80 px vertical clearance is wider than
    # the rabbit's sampled foot width after viewport scaling.
    # Normalize any antialiased edges from an authored/source mask before
    # adding the doorway connector. Runtime collision expects only 0/255.
    mask = mask.point(lambda value: 255 if value >= 128 else 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle((414, 670, 462, 750), fill=255)

    colors = set(mask.get_flattened_data())
    if not colors.issubset({0, 255}):
        raise ValueError(f"Walkmask is no longer binary: {sorted(colors)[:16]}")
    mask.save(MASK_PATH)


if __name__ == "__main__":
    main()
