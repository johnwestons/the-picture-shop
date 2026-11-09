"""Create a review guide for the single West 104-world-px stride correction attempt."""
from pathlib import Path
import hashlib
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
V4 = ROOT / "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/canonical-8phase-v4-empty-gap-registration/field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png"
OUT = Path(__file__).resolve().parent / "field-mouse-west-v4-contact-target-guide-4x2.png"
CELL = 256
TARGET_X = [104, 143, 182, 221, 104, 143, 182, 221]
TARGET_Y = 229
SCALE_ZOOM = 2
BG = (29, 33, 38)

def main():
    strip = Image.open(V4).convert("RGBA")
    canvas = Image.new("RGB", (4 * CELL * SCALE_ZOOM, 2 * CELL * SCALE_ZOOM), BG)
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    for i, x in enumerate(TARGET_X):
        cell = strip.crop((i * CELL, 0, (i + 1) * CELL, CELL))
        bg = Image.new("RGBA", cell.size, (*BG, 255))
        bg.alpha_composite(cell)
        shown = bg.resize((CELL * SCALE_ZOOM, CELL * SCALE_ZOOM), Image.Resampling.NEAREST)
        d = ImageDraw.Draw(shown)
        # Cell pixel x=128 torso axis and y=229 ground line, at 2x display zoom.
        d.line((128 * SCALE_ZOOM, 0, 128 * SCALE_ZOOM, 511), fill=(75, 110, 255), width=2)
        d.line((0, 229 * SCALE_ZOOM, 511, 229 * SCALE_ZOOM), fill=(255, 80, 80), width=2)
        px, py = x * SCALE_ZOOM, TARGET_Y * SCALE_ZOOM
        d.ellipse((px - 8, py - 8, px + 8, py + 8), outline=(45, 255, 245), width=4)
        d.line((px - 12, py, px + 12, py), fill=(45, 255, 245), width=2)
        d.line((px, py - 12, px, py + 12), fill=(45, 255, 245), width=2)
        gx, gy = (i % 4) * CELL * SCALE_ZOOM, (i // 4) * CELL * SCALE_ZOOM
        canvas.paste(shown.convert("RGB"), (gx, gy))
        # Prominent cell-coordinate labels above the artwork.
        draw.text((gx + 4, gy + 4), f"K{i+1} target sole cell=({x},229); torso axis=128", fill=(255, 239, 120), font=font)
    canvas.save(OUT, optimize=True)
    print(f"guide={OUT}\nsha256={hashlib.sha256(OUT.read_bytes()).hexdigest()}\nsource_strip_sha256={hashlib.sha256(V4.read_bytes()).hexdigest()}\ntargets={TARGET_X}")

if __name__ == "__main__":
    main()
