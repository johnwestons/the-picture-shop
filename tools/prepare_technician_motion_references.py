"""Extract reviewed identities and draw anatomical guides; never runtime art."""
from pathlib import Path
from PIL import Image
import build_visitor_gait_guides as guide

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/technician-motion-v2"
DIRECTIONS = ("east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast")
VECTORS = ((1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1))

def main():
    destination = SOURCE / "references"
    destination.mkdir(parents=True, exist_ok=True)
    for species in ("mouse", "lizard"):
        atlas = Image.open(SOURCE / f"{species}-idle.png").convert("RGBA")
        # The lizard generator swapped the two back diagonals. Select by the
        # visible camera view, preserving the source pixels and anatomical hand.
        order = list(range(8)) if species == "mouse" else [0,1,2,3,4,7,6,5]
        for direction, cell in zip(DIRECTIONS, order):
            col, row = cell % 4, cell // 4
            crop = atlas.crop((round(col*atlas.width/4), round(row*atlas.height/4),
                               round((col+1)*atlas.width/4), round((row+1)*atlas.height/4)))
            crop.save(destination / f"{species}-{direction}.png")
            if species=="mouse" and direction=="west":
                crop.save(destination/"mouse-west-original.png")
        corrected=SOURCE/"mouse-west-idle-v2.png"
        if species=="mouse" and corrected.exists():
            pair=Image.open(corrected).convert("RGBA")
            pair.crop((0,0,pair.width//2,pair.height)).save(destination/"mouse-west.png")
    contacts=SOURCE/"mouse-south-right-contacts.png"
    if contacts.exists():
        atlas=Image.open(contacts)
        # Only the upper row of this master has the right-leading stance.
        atlas.crop((0,0,atlas.width,atlas.height//2)).save(destination/"mouse-south-right-contacts-selected.png")
    for direction, vector in zip(DIRECTIONS, VECTORS):
        guide.VECTORS[direction] = vector
        diagram=guide.diagram(direction)
        diagram.save(destination / f"guide-{direction}.png")
        for half in range(2):
            sheet=Image.new("RGB",(600,620),"#f5f5fa")
            for index in range(4):
                cell=diagram.crop((index*300,half*310,(index+1)*300,(half+1)*310))
                sheet.paste(cell,((index%2)*300,(index//2)*310))
            sheet.save(destination / f"guide-{direction}-half-{half+1}.png")
    print(destination)

if __name__ == "__main__":
    main()
