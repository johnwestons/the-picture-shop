from pathlib import Path
import sys

from PIL import Image


def main() -> None:
    if len(sys.argv) not in (3, 5):
        raise SystemExit("usage: build_cutter_maintenance_assets.py SOURCE OUTPUT [WIDTH HEIGHT]")
    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    image = Image.open(source).convert("RGBA")
    size = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) == 5 else (512, 512)
    image = image.resize(size, Image.Resampling.LANCZOS)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)
    print(f"wrote {output} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
