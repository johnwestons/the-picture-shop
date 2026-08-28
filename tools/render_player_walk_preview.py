"""Render all eight directions at the exact configured walk or idle cadence."""

import argparse
from pathlib import Path
from typing import Sequence

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
FRAME_SIZE = 512


def directions(prefix: str) -> tuple[tuple[str, str, bool], ...]:
    return (
        ("NORTH", f"{prefix}_north", False),
        ("NORTHEAST", f"{prefix}_northeast", False),
        ("EAST", prefix, False),
        ("SOUTHEAST", f"{prefix}_southeast", False),
        ("SOUTH", f"{prefix}_south", False),
        ("SOUTHWEST", f"{prefix}_southeast", True),
        ("WEST", prefix, True),
        ("NORTHWEST", f"{prefix}_northeast", True),
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--character", default="rabbit-worker")
    parser.add_argument("--sprites", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--speed", type=float, default=155)
    parser.add_argument("--pixels-per-frame", type=float, default=20)
    parser.add_argument("--idle", action="store_true")
    parser.add_argument("--idle-rate", type=float, default=0.65)
    args = parser.parse_args(argv)
    prefix = "idle" if args.idle else "walk"
    frame_count = 2 if args.idle else 8
    frame_duration_ms = round(1000 / args.idle_rate) if args.idle \
        else round(1000 * args.pixels_per_frame / args.speed)
    sprite_root = (args.sprites or ROOT / "assets" / "generated" / "characters" / args.character).resolve()
    output = (args.output or ROOT / "output" / "sprite-doctor" / f"{args.character}-directional-{prefix}-preview.gif").resolve()
    direction_map = directions(prefix)
    strips = {action: Image.open(sprite_root / f"{action}.png").convert("RGBA")
              for _, action, _ in direction_map}
    frames = []
    for frame_index in range(frame_count):
        canvas = Image.new("RGB", (960, 520), (28, 33, 39))
        draw = ImageDraw.Draw(canvas)
        for index, (label, action, mirrored) in enumerate(direction_map):
            column, row = index % 4, index // 4
            sprite = strips[action].crop((frame_index * FRAME_SIZE, 0,
                                           (frame_index + 1) * FRAME_SIZE, FRAME_SIZE))
            if mirrored:
                sprite = sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            bounds = sprite.getchannel("A").getbbox()
            if not bounds:
                raise ValueError(f"empty frame: {action} {frame_index + 1}")
            sprite = sprite.crop(bounds)
            scale = min(150 / sprite.height, 190 / sprite.width)
            sprite = sprite.resize((round(sprite.width * scale), round(sprite.height * scale)),
                                   Image.Resampling.LANCZOS)
            x = column * 240 + (240 - sprite.width) // 2
            baseline = row * 260 + 220
            canvas.paste(sprite, (x, baseline - sprite.height), sprite)
            draw.text((column * 240 + 12, row * 260 + 12), label, fill=(235, 220, 150))
            draw.text((column * 240 + 12, row * 260 + 32),
                      f"FRAME {frame_index + 1}/{frame_count}", fill=(170, 184, 190))
        frames.append(canvas)
    output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(output, save_all=True, append_images=frames[1:], loop=0,
                   duration=frame_duration_ms, disposal=2)
    print(f"Rendered {output} at {frame_duration_ms} ms/frame")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
