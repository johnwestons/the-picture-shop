from pathlib import Path
from PIL import Image
from install_character_assets import remove_connected_background

root = Path(__file__).resolve().parents[1]
source = root / "assets/Machines/2colorPicturePress.png"
image = remove_connected_background(Image.open(source).convert("RGBA"))
image.save(root / "assets/generated/picture-press-transparent.png")
print("prepared picture press sprite")
