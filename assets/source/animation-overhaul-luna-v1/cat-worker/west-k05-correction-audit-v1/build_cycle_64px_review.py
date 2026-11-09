"""Build an anchored complete-cycle review for original and rejected West K5 attempts."""
from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
BATCH = Path(__file__).resolve().parent
OUT = ROOT / "output/animation-overhaul/luna-cat/view-audit/west-k05-correction-attempts"
WALK = ROOT / "assets/source/cat-worker-v1/locomotion/walk_west.png"
MANIFEST = ROOT / "output/animation-overhaul/luna-cat/view-audit/runtime-source-manifest.json"
POSES = ["L contact", "L down", "R passing", "R knee-up", "R contact", "R down", "L passing", "L knee-up"]
HEIGHT_PX = 64
GAME_SCALE = HEIGHT_PX / (2 * 194)  # Source master is 512px; runtime West action max height is 194/256.
TILE = (96, 96)
BASELINE = 78


def frames(path: Path) -> list[Image.Image]:
    strip = Image.open(path).convert("RGBA")
    if strip.size != (4096, 512):
        raise ValueError(f"Expected West source master 4096x512, got {strip.size}")
    return [strip.crop((i * 512, 0, (i + 1) * 512, 512)) for i in range(8)]


def checker(size: tuple[int, int], cell: int = 8) -> Image.Image:
    image = Image.new("RGBA", size, (218, 218, 218, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(184, 184, 184, 255))
    return image


def render(frame: Image.Image, anchor: tuple[float, float], scale: float = GAME_SCALE) -> Image.Image:
    resized = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.NEAREST)
    tile = Image.new("RGBA", TILE, (0, 0, 0, 0))
    left = round(TILE[0] / 2 - anchor[0] * scale)
    top = round(BASELINE - anchor[1] * scale)
    tile.alpha_composite(resized, (left, top))
    return tile


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    original = frames(WALK)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    anchors256 = manifest["source_runtime_files"]["west"]["anchors"]
    anchors512 = [(x * 2, y * 2) for x, y in anchors256]
    normalized_candidates = {
        "attempt 1 rejected": Image.open(OUT / "attempt-01-full-pose-rigid-review-only.png").convert("RGBA"),
        "attempt 2 rejected": Image.open(OUT / "attempt-02-source-edit-rigid-review-only.png").convert("RGBA"),
        "attempt 3 rejected": Image.open(OUT / "attempt-03-owner-guide-edit-rigid-review-only.png").convert("RGBA"),
    }
    variants = {"original": original}
    for label, candidate in normalized_candidates.items():
        cells = list(original)
        cells[4] = candidate
        variants[label] = cells

    font = ImageFont.load_default()
    board = Image.new("RGB", (8 * TILE[0], 32 + len(variants) * (TILE[1] + 20)), (42, 44, 48))
    draw = ImageDraw.Draw(board)
    for col, pose in enumerate(POSES):
        draw.text((col * TILE[0] + 2, 8), f"K{col + 1} {pose}", fill=(245, 240, 220), font=font)
    for row, (label, cells) in enumerate(variants.items()):
        y = 32 + row * (TILE[1] + 20)
        draw.text((4, y + 2), label, fill=(245, 240, 220), font=font)
        y += 20
        for col, cell in enumerate(cells):
            layer = checker(TILE)
            layer.alpha_composite(render(cell, anchors512[col]))
            board.paste(layer.convert("RGB"), (col * TILE[0], y))
            draw.rectangle((col * TILE[0], y, col * TILE[0] + TILE[0] - 1, y + TILE[1] - 1), outline=(90, 94, 100))
    board.save(OUT / "west-complete-cycle-64px-review.png")

    triplet = Image.new("RGB", (3 * TILE[0], 32 + len(variants) * (TILE[1] + 20)), (42, 44, 48))
    draw = ImageDraw.Draw(triplet)
    for col, phase in enumerate((3, 4, 5)):
        draw.text((col * TILE[0] + 2, 8), f"K{phase + 1} {POSES[phase]}", fill=(245, 240, 220), font=font)
    for row, (label, cells) in enumerate(variants.items()):
        y = 32 + row * (TILE[1] + 20)
        draw.text((4, y + 2), label, fill=(245, 240, 220), font=font)
        y += 20
        for col, phase in enumerate((3, 4, 5)):
            layer = checker(TILE)
            layer.alpha_composite(render(cells[phase], anchors512[phase]))
            triplet.paste(layer.convert("RGB"), (col * TILE[0], y))
            draw.rectangle((col * TILE[0], y, col * TILE[0] + TILE[0] - 1, y + TILE[1] - 1), outline=(90, 94, 100))
    triplet.save(OUT / "west-k04-k05-k06-64px-review.png")

    # Source-resolution close-ups retain enough ankle overlap to inspect ownership.
    foot_closeups = [
        ("K1 source left contact", original[0]),
        ("K5 source right contact", original[4]),
        ("K5 attempt 1", normalized_candidates["attempt 1 rejected"]),
        ("K5 attempt 2", normalized_candidates["attempt 2 rejected"]),
        ("K5 attempt 3", normalized_candidates["attempt 3 rejected"]),
    ]
    crop = (88, 280, 424, 476)
    zoom = 4
    close_w = (crop[2] - crop[0]) * zoom
    close_h = (crop[3] - crop[1]) * zoom
    close = Image.new("RGB", (2 * close_w, 32 + math.ceil(len(foot_closeups) / 2) * close_h), (42, 44, 48))
    draw = ImageDraw.Draw(close)
    for index, (label, cell) in enumerate(foot_closeups):
        col, row = index % 2, index // 2
        x, y = col * close_w, 32 + row * close_h
        draw.text((x + 4, y - 22), label, fill=(245, 240, 220), font=font)
        layer = checker((512, 512))
        layer.alpha_composite(cell)
        detail = layer.crop(crop).resize((close_w, close_h), Image.Resampling.NEAREST)
        close.paste(detail.convert("RGB"), (x, y))
    close.save(OUT / "west-contact-owner-feet-4x.png")

    triplet_close = Image.new("RGB", (3 * close_w, 32 + len(variants) * close_h), (42, 44, 48))
    draw = ImageDraw.Draw(triplet_close)
    for row, (label, cells) in enumerate(variants.items()):
        y = 32 + row * close_h
        draw.text((4, y - 22), label, fill=(245, 240, 220), font=font)
        for col, phase in enumerate((3, 4, 5)):
            x = col * close_w
            layer = checker((512, 512))
            layer.alpha_composite(cells[phase])
            detail = layer.crop(crop).resize((close_w, close_h), Image.Resampling.NEAREST)
            triplet_close.paste(detail.convert("RGB"), (x, y))
            draw.rectangle((x, y, x + close_w - 1, y + close_h - 1), outline=(90, 94, 100))
            draw.text((x + 4, y + close_h - 18), f"K{phase + 1}", fill=(245, 240, 220), font=font)
    triplet_close.save(OUT / "west-k04-k05-k06-feet-4x.png")

    # A labeled leg-owner aid for a bounded K5 proposal; colors are annotations, not sprite pixels.
    guide = Image.new("RGB", (2 * 512, 32 + 2 * 512), (42, 44, 48))
    draw = ImageDraw.Draw(guide)
    near_color, far_color = (54, 220, 116), (72, 145, 255)
    guide_panels = [
        ("K1: near/left supports; far/right trails", original[0], ((155, 449), near_color), ((292, 449), far_color)),
        ("K4: far/right knee-up; near/left supports", original[3], ((205, 408), far_color), ((309, 449), near_color)),
        ("K5 desired: far/right supports; near/left trails", original[4], ((148, 449), far_color), ((294, 431), near_color)),
        ("K6: far/right remains support", original[5], ((149, 449), far_color), ((294, 449), near_color)),
    ]
    for index, (label, cell, point1, point2) in enumerate(guide_panels):
        col, row = index % 2, index // 2
        x, y = col * 512, 32 + row * 512
        draw.text((x + 4, y - 22), label, fill=(245, 240, 220), font=font)
        layer = checker((512, 512), cell=16)
        layer.alpha_composite(cell)
        guide.paste(layer.convert("RGB"), (x, y))
        for point, color in (point1, point2):
            px, py = x + point[0], y + point[1]
            draw.ellipse((px - 12, py - 12, px + 12, py + 12), outline=color, width=6)
            draw.line((px, py + 12, px, py + 34), fill=color, width=6)
    draw.text((6, guide.height - 18), "Green = near/left leg; blue = far/right leg. K5 target reverses the grounded owner.", fill=(245, 240, 220), font=font)
    guide.save(OUT / "west-k05-leg-owner-guide.png")

    for label, cells in variants.items():
        animation = []
        for index, cell in enumerate(cells):
            layer = checker((128, 104), cell=8)
            # Use the same 64px character scale and fixed source anchor; present an in-place stride.
            resized = cell.resize((round(512 * GAME_SCALE), round(512 * GAME_SCALE)), Image.Resampling.NEAREST)
            left = round(64 - anchors512[index][0] * GAME_SCALE)
            top = round(84 - anchors512[index][1] * GAME_SCALE)
            layer.alpha_composite(resized, (left, top))
            animation.append(layer.convert("RGB"))
        slug = "source" if label == "original" else ("attempt-01" if label.startswith("attempt 1") else ("attempt-02" if label.startswith("attempt 2") else "attempt-03"))
        animation[0].save(OUT / f"west-cycle-64px-{slug}-nominal.gif", save_all=True, append_images=animation[1:], duration=180, loop=0, disposal=2)
        animation[0].save(OUT / f"west-cycle-64px-{slug}-half-speed.gif", save_all=True, append_images=animation[1:], duration=360, loop=0, disposal=2)

    print(json.dumps({
        "source_sha256": __import__("hashlib").sha256(WALK.read_bytes()).hexdigest(),
        "anchors256": anchors256,
        "fixed_scale_source512_to_64px": GAME_SCALE,
        "fixed_scale_runtime256_to_64px": GAME_SCALE * 2,
        "output": OUT.as_posix(),
        "variants": list(variants),
    }, indent=2))


if __name__ == "__main__":
    main()
