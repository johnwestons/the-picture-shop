"""Create the binary walkmask for the v2 warehouse layout."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
MASK_PATH = ROOT / "assets" / "generated" / "warehouse-layout-v4-walkmask.png"
SIZE = (1536, 1024)


def main() -> None:
    mask = Image.new("L", SIZE, 0)
    draw = ImageDraw.Draw(mask)

    # Main open factory floor, kept inside the platform rim.
    draw.polygon(
        [(45, 430), (720, 330), (1492, 465), (1492, 770), (920, 1000), (55, 665)],
        fill=255,
    )

    # Loading dock apron at upper left and its clear route to the factory.
    draw.polygon([(170, 350), (510, 380), (535, 470), (185, 455)], fill=255)
    draw.polygon([(185, 430), (540, 445), (565, 520), (160, 500)], fill=255)

    # Separate office room and the wide open doorway into it.
    draw.polygon([(670, 275), (925, 315), (918, 425), (690, 402)], fill=255)
    draw.polygon([(680, 385), (925, 395), (930, 470), (680, 445)], fill=255)

    # Separate lobby/reception room and its wide open doorway.
    draw.polygon([(925, 330), (1500, 445), (1495, 640), (1230, 560), (925, 445)], fill=255)
    draw.polygon([(895, 418), (1010, 440), (1000, 505), (895, 475)], fill=255)

    # Main double-glass entrance threshold in the former partition opening.
    draw.polygon([(930, 350), (1055, 372), (1050, 445), (925, 423)], fill=255)

    # Fixed office furniture is not walkable even though it sits on walkable floors.
    draw.polygon([(700, 285), (842, 305), (842, 350), (710, 333)], fill=0)
    # Client lounge furniture: couch, two armchairs, and low table. Seat
    # approach points remain walkable in front of each piece.
    draw.polygon([(1210, 365), (1398, 395), (1394, 478), (1218, 450)], fill=0)
    draw.polygon([(1115, 390), (1210, 415), (1205, 485), (1120, 468)], fill=0)
    draw.polygon([(1385, 485), (1480, 518), (1474, 590), (1390, 558)], fill=0)
    draw.polygon([(1245, 475), (1375, 500), (1365, 560), (1250, 538)], fill=0)

    rgba = Image.merge("RGBA", (mask, mask, mask, Image.new("L", SIZE, 255)))
    rgba.save(MASK_PATH)

    colors = set(mask.getdata())
    if colors != {0, 255}:
        raise ValueError(f"Walkmask is no longer binary: {sorted(colors)}")


if __name__ == "__main__":
    main()
