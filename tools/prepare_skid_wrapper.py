from pathlib import Path
from PIL import Image
from install_character_assets import remove_connected_background
root = Path(__file__).resolve().parents[1]
for source_name, output_name in [("stretchWrapper.png", "skid-wrapper-transparent.png"), ("stretchWrapper2.png", "skid-wrapper-iso-transparent.png")]:
    image = Image.open(root / "assets/Machines" / source_name).convert("RGBA")
    remove_connected_background(image).save(root / "assets/generated" / output_name)
    print(f"prepared {output_name}")
