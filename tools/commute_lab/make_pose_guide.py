"""Anatomy diagram for sprite authoring, never runtime art or a painted repair."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/commute-rider-pose-guide'
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 256
image = Image.new('RGB', (SIZE * 4, SIZE * 2), '#f2eee5')
draw = ImageDraw.Draw(image)
# Coordinates authored in a 512px diagram; tuples follow knee, ankle, toe.
support = [((295, 347), (335, 425), (366, 415)),
           ((280, 365), (300, 430), (333, 430)),
           ((253, 365), (245, 430), (278, 430)),
           ((222, 362), (195, 430), (228, 430))]
swing = [((215, 355), (175, 407), (195, 430)),
         ((215, 370), (185, 394), (180, 420)),
         ((267, 352), (230, 400), (263, 400)),
         ((300, 330), (305, 390), (338, 390))]
forward_arms = [((290, 266), (319, 280)), ((277, 270), (292, 299)),
                ((258, 270), (260, 310)), ((216, 263), (195, 290))]
back_arms = [((216, 263), (195, 290)), ((225, 273), (213, 306)),
             ((244, 270), (241, 310)), ((290, 266), (319, 280))]
names = ['LEFT CONTACT', 'LEFT DOWN', 'RIGHT PASSING', 'RIGHT UP',
         'RIGHT CONTACT', 'RIGHT DOWN', 'LEFT PASSING', 'LEFT UP']
for frame in range(8):
    col, row = frame % 4, frame // 4
    ox, oy = col * SIZE, row * SIZE
    phase = frame % 4
    bob = [0, 8, 0, -8][phase]
    def point(p):
        return (round(ox + p[0] * .5), round(oy + p[1] * .5))
    def line(points, color, width):
        draw.line([point(p) for p in points], fill=color, width=width, joint='curve')
    def limb(points, color):
        line(points, color, 9)
        for p in points[:-1]:
            x, y = point(p)
            draw.ellipse((x-5, y-5, x+5, y+5), fill=color, outline='#242a2e', width=1)
    far, near = (support[phase], swing[phase]) if frame < 4 else (swing[phase], support[phase])
    far_arm, near_arm = (back_arms[phase], forward_arms[phase]) if frame < 4 else (forward_arms[phase], back_arms[phase])
    # Far limbs first, then torso, then near limbs: visible occlusion is explicit.
    limb([(244, 293+bob), *far], '#bd5555')
    limb([(244, 216+bob), *far_arm], '#bd5555')
    line([(250, 211+bob), (250, 294+bob)], '#626c70', 25)
    x, y = point((250, 151+bob))
    draw.ellipse((x-27, y-31, x+29, y+29), fill='#b4b8b5', outline='#242a2e', width=2)
    draw.rectangle((x+12, y-11, x+29, y+5), fill='#242a2e')
    limb([(256, 293+bob), *near], '#347da9')
    limb([(256, 216+bob), *near_arm], '#347da9')
    draw.text((ox+8, oy+6), f'{frame+1} {names[frame]}', fill='#242a2e')
    draw.text((ox+8, oy+233), 'BLUE near RIGHT / RED far LEFT', fill='#242a2e')
    line([(70, 432), (440, 432)], '#b9bbb4', 1)
image.save(OUT / 'east-eight-phase-guide.png')
print(OUT / 'east-eight-phase-guide.png')
