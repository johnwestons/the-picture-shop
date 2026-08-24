"""Create non-destructive doctor staging strips from the supplied 1024px panels."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets" / "Characters"
STAGE_ROOT = ROOT / "output" / "sprite-doctor" / "character-staging"


SETS = {
    "tan-cat": ("tanCatagainCat.png", "tanCatagainCatWalking.png", "tanCatagainCatSitting.png"),
    "green-blazer-cat": ("greenBlazerCat.png", "greenBlazerCatWalking.png", "greenBlazerCatSitting.png"),
    "blue-coaler-cat": ("blueCoalerCat.jpg", "blueCoalerCatWalking.png", "blueCoalerCatSitting.png"),
}


def split_strip(path: Path) -> list[Image.Image]:
    image = Image.open(path).convert("RGBA")
    if image.width % 2:
        raise ValueError(f"Expected two equal panels: {path}")
    width = image.width // 2
    return [image.crop((index * width, 0, (index + 1) * width, image.height)) for index in range(2)]


def assemble(frames: list[Image.Image], output: Path) -> None:
    canvas = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        canvas.alpha_composite(frame, (index * frame.width, 0))
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output)


def main() -> None:
    for character, (base_name, walk_name, sit_name) in SETS.items():
        character_dir = STAGE_ROOT / character
        base = Image.open(SOURCE_ROOT / base_name).convert("RGBA")
        assemble([base, base.copy()], character_dir / "idle-source.png")
        walk = split_strip(SOURCE_ROOT / "Animations" / walk_name)
        assemble([walk[0], walk[1], walk[0].copy()], character_dir / "walk-source.png")
        sit = split_strip(SOURCE_ROOT / "Animations" / sit_name)
        assemble(sit, character_dir / "sit-source.png")
        if character == "green-blazer-cat":
            newspaper = split_strip(SOURCE_ROOT / "Animations" / "greenBlazerCatNewspaper.png")
            assemble([newspaper[0], newspaper[1], newspaper[0].copy()], character_dir / "use-source.png")


if __name__ == "__main__":
    main()
