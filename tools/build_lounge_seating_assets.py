"""Build exact lounge-furniture foreground sprites from the warehouse art.

The lounge furniture is baked into the warehouse background. These small
transparent crops repeat only the portions that must render in front of a
seated client, so the client appears inside the chair and behind the table.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "generated" / "warehouse-layout-final.png"
OUTPUT = ROOT / "assets" / "generated" / "lounge"


SPRITES = {
    "left-chair-foreground.png": {
        "box": (1118, 375, 1214, 458),
        "polygons": (
            ((1125, 392), (1141, 398), (1141, 403), (1162, 411),
             (1162, 451), (1125, 438)),
            ((1173, 382), (1189, 388), (1189, 394), (1207, 400),
             (1207, 431), (1193, 436), (1193, 407), (1173, 399)),
            ((1158, 418), (1195, 404), (1195, 430), (1158, 445)),
        ),
    },
    "coffee-table-foreground.png": {
        "box": (1200, 410, 1326, 501),
        "polygons": (
            ((1205, 432), (1262, 413), (1321, 447), (1266, 476)),
            ((1207, 437), (1267, 470), (1267, 487), (1207, 453)),
            ((1267, 470), (1322, 448), (1322, 464), (1267, 489)),
            ((1213, 446), (1225, 450), (1225, 486), (1214, 486)),
            ((1260, 469), (1274, 469), (1274, 499), (1260, 499)),
            ((1308, 453), (1322, 449), (1322, 486), (1309, 489)),
        ),
    },
    "right-chair-foreground.png": {
        "box": (1324, 443, 1443, 543),
        "polygons": (
            ((1330, 478), (1353, 485), (1365, 472), (1380, 479),
             (1361, 506), (1329, 496)),
            ((1365, 461), (1383, 467), (1409, 450), (1423, 455),
             (1390, 477), (1371, 471)),
            ((1329, 490), (1394, 510), (1394, 538), (1329, 520)),
            ((1336, 515), (1349, 518), (1349, 540), (1336, 538)),
            ((1380, 527), (1393, 528), (1393, 542), (1380, 542)),
        ),
    },
}


def build_sprite(source: Image.Image, box: tuple[int, int, int, int],
                 polygons: tuple[tuple[tuple[int, int], ...], ...]) -> Image.Image:
    mask = Image.new("L", source.size, 0)
    draw = ImageDraw.Draw(mask)
    for polygon in polygons:
        draw.polygon(polygon, fill=255)
    extracted = Image.new("RGBA", source.size, (0, 0, 0, 0))
    extracted.paste(source, (0, 0), mask)
    sprite = extracted.crop(box)
    # The masks deliberately extend one or two pixels past the furniture so
    # its antialiased edge is never clipped. Remove only the unmistakably
    # green rug/wall pixels caught by that safety margin.
    pixels = sprite.load()
    for y in range(sprite.height):
        for x in range(sprite.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and green > red and green > blue:
                pixels[x, y] = (red, green, blue, 0)
    return sprite


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != (1536, 1024):
        raise ValueError(f"warehouse must be 1536x1024, got {source.size}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, definition in SPRITES.items():
        sprite = build_sprite(source, definition["box"], definition["polygons"])
        destination = OUTPUT / name
        sprite.save(destination)
        print(f"built {destination.relative_to(ROOT)} ({sprite.width}x{sprite.height})")


if __name__ == "__main__":
    main()
