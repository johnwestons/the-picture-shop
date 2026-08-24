"""Normalize rabbit walk-frame horizontal anchors inside the 6x4 atlas."""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ATLAS = ROOT / "assets/generated/rabbit-worker-atlas.png"

def main() -> None:
    image = Image.open(ATLAS).convert("RGBA")
    width, height = image.size
    cell_width, cell_height = width // 6, height // 4
    alpha = image.getchannel("A")
    frames = []
    centers = []
    for column in range(6):
        box = (column * cell_width, cell_height, (column + 1) * cell_width, cell_height * 2)
        frame = image.crop(box)
        bbox = alpha.crop(box).getbbox()
        if bbox is None:
            raise ValueError(f"empty walk frame {column + 1}")
        frames.append(frame)
        centers.append((bbox[0] + bbox[2]) / 2)
    target = sum(centers) / len(centers)
    for column, (frame, center) in enumerate(zip(frames, centers)):
        shift = round(target - center)
        normalized = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
        normalized.alpha_composite(frame, (shift, 0))
        image.paste((0, 0, 0, 0), (column * cell_width, cell_height, (column + 1) * cell_width, cell_height * 2))
        image.paste(normalized, (column * cell_width, cell_height), normalized)
    image.save(ATLAS)
    print(f"normalized walk anchors target={target:.2f} centers={centers}")

if __name__ == "__main__":
    main()
