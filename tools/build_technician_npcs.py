"""Normalize the approved generated technician atlas into an exact 4x2 runtime grid."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "technician-npcs-source-v1.png"
DESTINATION = ROOT / "assets" / "generated" / "technician-npcs-atlas-v1.png"


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    output = Image.new("RGBA", (2048, 1024), (0, 0, 0, 0))
    for row in range(2):
        for column in range(4):
            left = round(column * source.width / 4)
            right = round((column + 1) * source.width / 4)
            top = round(row * source.height / 2)
            bottom = round((row + 1) * source.height / 2)
            frame = source.crop((left, top, right, bottom)).resize((512, 512), Image.Resampling.LANCZOS)
            output.alpha_composite(frame, (column * 512, row * 512))
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    output.save(DESTINATION)
    print(DESTINATION.relative_to(ROOT))
    for row, species in enumerate(("mouse", "lizard")):
        bounds = []
        for column in range(4):
            frame = output.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512))
            bounds.append(frame.getchannel("A").getbbox())
        print(species, bounds)


if __name__ == "__main__":
    main()
