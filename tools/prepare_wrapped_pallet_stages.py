"""Normalize the three generated pallet-wrapping stages into 512px cells."""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/Machines/wrapped-pallet-stages-source.png"
DESTINATION = ROOT / "assets/generated/wrapped-pallet-stages-strip.png"

def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    result = Image.new("RGBA", (1536, 512), (0, 0, 0, 0))
    for index in range(3):
        left = round(index * source.width / 3)
        right = round((index + 1) * source.width / 3)
        panel = source.crop((left, 0, right, source.height))
        bbox = panel.getchannel("A").getbbox()
        if not bbox:
            raise ValueError(f"wrapping stage {index + 1} is empty")
        subject = panel.crop(bbox)
        scale = min(472 / subject.width, 472 / subject.height)
        subject = subject.resize((round(subject.width * scale), round(subject.height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        frame.alpha_composite(subject, ((512 - subject.width) // 2, 492 - subject.height))
        result.alpha_composite(frame, (index * 512, 0))
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    result.save(DESTINATION)
    print(f"prepared {DESTINATION.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
