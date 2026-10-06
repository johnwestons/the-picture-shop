"""Draw anatomical pose diagrams used as references for authored visitor art.

These diagrams never enter the character runtime; ImageGen authors the sprites.
Orange identifies anatomical left, blue identifies anatomical right.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "references" / "animation" / "visitor-gait"
VECTORS = {
    "north": (0, -1), "northeast": (1, -1), "east": (1, 0),
    "southeast": (1, 1), "south": (0, 1),
}
PHASES = (
    ("LEFT contact", 13, 0, -13, 0, 0),
    ("LEFT load", 9, 0, -10, 5, -2),
    ("RIGHT passing", -1, 0, 0, 9, 0),
    ("RIGHT knee up", -9, 0, 9, 13, 2),
    ("RIGHT contact", -13, 0, 13, 0, 0),
    ("RIGHT load", -10, 5, 9, 0, -2),
    ("LEFT passing", 0, 9, -1, 0, 0),
    ("LEFT knee up", 9, 13, -9, 0, 2),
)
LEFT, RIGHT, BODY = "#df681f", "#167bc5", "#686b78"


def diagram(direction: str) -> Image.Image:
    image = Image.new("RGB", (1200, 680), "#f5f5fa")
    draw = ImageDraw.Draw(image)
    draw.text((18, 10), f"ANATOMICAL WALK GUIDE: {direction.upper()}", fill="#232833")
    draw.text((18, 28), "Orange = LEFT limbs. Blue = RIGHT limbs. Colors and labels are not costume art.", fill="#232833")
    vx, vy = VECTORS[direction]
    length = math.hypot(vx, vy)
    forward = vx / length, vy / length
    left = forward[1], -forward[0]

    for index, (label, lf, lz, rf, rz, bounce) in enumerate(PHASES):
        column, row = index % 4, index // 4
        center_x, baseline = column * 300 + 150, row * 310 + 295
        scale = 2.55

        def point(lateral: float, along: float, height: float) -> tuple[float, float]:
            x = left[0] * lateral + forward[0] * along
            y = left[1] * lateral + forward[1] * along
            return center_x + x * scale, baseline + (y * 0.48 - height) * scale

        draw.text((column * 300 + 24, row * 310 + 64), f"{index + 1}: {label}", fill="#232833")
        draw.line((column * 300 + 25, baseline, column * 300 + 275, baseline), fill="#ced3df", width=1)

        def leg(lateral: float, along: float, lift: float, color: str) -> None:
            hip = point(lateral, 0, 28 + bounce)
            knee = point(lateral, along * 0.52 + (5 if lift else 2), 15 + lift * 0.4 + bounce * 0.45)
            ankle = point(lateral, along, lift + 2)
            draw.line((hip, knee, ankle), fill=color, width=9)
            foot = [point(lateral - 2.7, along - 3, lift), point(lateral + 2.7, along - 3, lift),
                    point(lateral + 2.7, along + 6, lift), point(lateral - 2.7, along + 6, lift)]
            draw.polygon(foot, fill=color, outline="#303542")

        # Draw the farther side first using world depth, not limb names.
        limbs = [(7, lf, lz, LEFT), (-7, rf, rz, RIGHT)]
        limbs.sort(key=lambda item: left[1] * item[0])
        for values in limbs:
            leg(*values)

        torso = [point(-8, 0, 29 + bounce), point(8, 0, 29 + bounce),
                 point(10, 0, 58 + bounce), point(-10, 0, 58 + bounce)]
        draw.polygon(torso, fill=BODY, outline="#303542")
        head_x, head_y = point(0, 0, 70 + bounce)
        draw.ellipse((head_x - 19, head_y - 19, head_x + 19, head_y + 19), fill="#a5a9b4", outline="#303542", width=2)
        facing_tip = point(0, 10, 70 + bounce)
        draw.line(((head_x, head_y), facing_tip), fill="#333744", width=3)
        for lateral, leg_forward, color in ((11, lf, LEFT), (-11, rf, RIGHT)):
            shoulder = point(lateral, 0, 55 + bounce)
            elbow = point(lateral, -leg_forward * 0.45, 43 + bounce)
            hand = point(lateral, -leg_forward * 0.9, 33 + bounce)
            draw.line((shoulder, elbow, hand), fill=color, width=7)
            draw.ellipse((hand[0] - 5, hand[1] - 5, hand[0] + 5, hand[1] + 5), fill=color)
    return image


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for direction in VECTORS:
        destination = DESTINATION / f"{direction}.png"
        diagram(direction).save(destination)
        print(destination.relative_to(ROOT))


if __name__ == "__main__":
    main()
