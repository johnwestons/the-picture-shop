"""Rebuild sitting strips from the supplied full-canvas sitting artwork."""

from pathlib import Path
from PIL import Image
from install_character_assets import remove_connected_background

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "tan-cat": ROOT / "assets/Characters/Animations/tanCatagainCatSitting.png",
    "green-blazer-cat": ROOT / "assets/Characters/Animations/greenBlazerCatSitting.png",
    "blue-coaler-cat": ROOT / "assets/Characters/Animations/blueCoalerCatSitting.png",
}

def main() -> None:
    for character, source in SOURCES.items():
        frame = Image.open(source).convert("RGBA").resize((512, 512), Image.Resampling.LANCZOS)
        frame = remove_connected_background(frame)
        strip = Image.new("RGBA", (1024, 512), (0, 0, 0, 0))
        strip.alpha_composite(frame, (0, 0))
        strip.alpha_composite(frame, (512, 0))
        destination = ROOT / "assets/generated/characters" / character / "sit.png"
        strip.save(destination)
        print(f"rebuilt {destination.relative_to(ROOT)}")

if __name__ == "__main__":
    main()
