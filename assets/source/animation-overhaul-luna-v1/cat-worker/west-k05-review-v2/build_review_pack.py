"""Build a source-only, labeled West K5 review pack; never writes runtime art."""
from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
BATCH = Path(__file__).resolve().parent
REFS = BATCH / "references"
OUT = BATCH / "review"
WALK = ROOT / "assets/source/cat-worker-v1/locomotion/walk_west.png"
IDLE = ROOT / "assets/source/cat-worker-v1/locomotion/idle_west.png"
RUNTIME_MANIFEST = ROOT / "output/animation-overhaul/luna-cat/view-audit/runtime-source-manifest.json"
PROMPT_FILE = BATCH / "prompt-west-k05-correction.txt"
GENERATION_META = BATCH / "generation-result.json"
POSES = ["L contact", "L down", "R passing", "R knee-up", "R contact", "R down", "L passing", "L knee-up"]
NEAR = (52, 205, 108)
FAR = (60, 135, 250)
SCALE_512_TO_64 = 64 / (2 * 194)
TILE = (96, 96)
BASELINE = 78


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def alpha16_bbox(image: Image.Image):
    return image.getchannel("A").point(lambda value: 255 if value >= 16 else 0).getbbox()


def checker(size: tuple[int, int], cell: int = 16) -> Image.Image:
    image = Image.new("RGBA", size, (218, 218, 218, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(184, 184, 184, 255))
    return image


def draw_arrow(draw: ImageDraw.ImageDraw, origin: tuple[int, int], target: tuple[int, int], color: tuple[int, int, int]):
    draw.line((origin, target), fill=color, width=8)
    dx, dy = target[0] - origin[0], target[1] - origin[1]
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    tip = target
    back = (target[0] - ux * 24, target[1] - uy * 24)
    points = [tip, (round(back[0] + px * 14), round(back[1] + py * 14)), (round(back[0] - px * 14), round(back[1] - py * 14))]
    draw.polygon(points, fill=color)


def render64(frame: Image.Image, anchor: tuple[float, float]) -> Image.Image:
    resized = frame.resize((round(frame.width * SCALE_512_TO_64), round(frame.height * SCALE_512_TO_64)), Image.Resampling.NEAREST)
    tile = Image.new("RGBA", TILE, (0, 0, 0, 0))
    tile.alpha_composite(resized, (round(TILE[0] / 2 - anchor[0] * SCALE_512_TO_64), round(BASELINE - anchor[1] * SCALE_512_TO_64)))
    return tile


def alpha_audit(image: Image.Image) -> dict:
    alpha = image.getchannel("A")
    width, height = image.size
    edge_points = []
    for x in range(width):
        edge_points.extend((image.getpixel((x, 0)), image.getpixel((x, height - 1))) )
    for y in range(height):
        edge_points.extend((image.getpixel((0, y)), image.getpixel((width - 1, y))))
    visible_edges = [px for px in edge_points if px[3] >= 16]
    return {
        "size": list(image.size),
        "mode": image.mode,
        "alpha_extrema": list(alpha.getextrema()),
        "alpha16_bbox": list(alpha16_bbox(image)) if alpha16_bbox(image) else None,
        "transparent_pixels": sum(1 for a in alpha.get_flattened_data() if a == 0),
        "partial_alpha_pixels": sum(1 for a in alpha.get_flattened_data() if 0 < a < 255),
        "visible_edge_pixels_alpha16": len(visible_edges),
        "magenta_edge_pixels_alpha16": sum(1 for r, g, b, a in visible_edges if a >= 16 and r >= 90 and b >= 90 and g <= 100),
    }


def rigid_review_frame(candidate: Image.Image, target: Image.Image) -> tuple[Image.Image, dict]:
    cb, tb = alpha16_bbox(candidate), alpha16_bbox(target)
    if not cb or not tb:
        raise ValueError("Candidate or original K5 has no alpha16 pixels")
    scale = (tb[3] - tb[1]) / (cb[3] - cb[1])
    resized = candidate.resize((round(candidate.width * scale), round(candidate.height * scale)), Image.Resampling.NEAREST)
    rb = tuple(round(v * scale) for v in cb)
    tx = round((tb[0] + tb[2] - rb[0] - rb[2]) / 2)
    ty = tb[3] - rb[3]
    result = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    result.alpha_composite(resized, (tx, ty))
    return result, {"uniform_scale": scale, "translation_xy": [tx, ty], "target_bbox_alpha16": list(tb), "source_bbox_alpha16": list(cb)}


def main():
    BATCH.mkdir(parents=True, exist_ok=True)
    REFS.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    strip = Image.open(WALK).convert("RGBA")
    if strip.size != (4096, 512):
        raise ValueError(f"Expected West source master 4096×512; got {strip.size}")
    cells = [strip.crop((i * 512, 0, (i + 1) * 512, 512)) for i in range(8)]
    for phase, image in enumerate(cells, start=1):
        image.save(REFS / f"walk_west_k{phase:02d}_source.png")
    idle = Image.open(IDLE).convert("RGBA")
    idle.crop((0, 0, 512, 512)).save(REFS / "idle_west_identity_source.png")

    # Two-by-two evidence board. Arrows/labels annotate screen position and owner; never sprite pixels.
    guide_cases = [
        ("K1 left contact", cells[0], [((116, 492), (156, 450), NEAR, "near/left planted"), ((380, 494), (300, 452), FAR, "far/right trails")]),
        ("K4 right knee-up", cells[3], [((132, 492), (208, 414), FAR, "far/right lifts"), ((388, 494), (310, 451), NEAR, "near/left supports")]),
        ("K5 desired right contact", cells[4], [((114, 492), (150, 450), FAR, "far/right plants"), ((385, 492), (292, 432), NEAR, "near/left trails lifted")]),
        ("K6 right weight-down", cells[5], [((112, 492), (150, 450), FAR, "far/right stays planted"), ((385, 492), (294, 450), NEAR, "near/left")]),
    ]
    guide = Image.new("RGB", (1024, 32 + 2 * 512), (42, 44, 48))
    draw = ImageDraw.Draw(guide)
    font = ImageFont.load_default()
    for index, (title, image, arrows) in enumerate(guide_cases):
        col, row = index % 2, index // 2
        x, y = col * 512, 32 + row * 512
        draw.text((x + 5, y - 22), title, fill=(245, 240, 220), font=font)
        layer = checker((512, 512))
        layer.alpha_composite(image)
        guide.paste(layer.convert("RGB"), (x, y))
        for origin, target, color, label in arrows:
            draw_arrow(draw, (x + origin[0], y + origin[1]), (x + target[0], y + target[1]), color)
            draw.text((x + origin[0] - 75, y + origin[1] - 20), label, fill=color, font=font)
    guide.save(REFS / "west_k05_explicit_owner_map.png")

    # Detailed source checker contact, showing authored K4/K5/K6 and labeled viewer positions.
    selected = [(1, "K1 near/left planted"), (4, "K4 far/right knee-up"), (5, "K5 original"), (6, "K6 far/right down")]
    cell_w = 512
    board = Image.new("RGB", (len(selected) * cell_w, 32 + 512), (42, 44, 48))
    draw = ImageDraw.Draw(board)
    draw.text((6, 5), "West faces viewer-left. Viewer-left is forward; viewer-right is trailing. Near/left = green, far/right = blue.", fill=(245, 240, 220), font=font)
    for col, (phase, label) in enumerate(selected):
        x = col * cell_w
        tile = checker((512, 512))
        tile.alpha_composite(cells[phase - 1])
        board.paste(tile.convert("RGB"), (x, 32))
        draw.text((x + 5, 17), label, fill=(245, 240, 220), font=font)
    board.save(OUT / "west-source-owner-contact-checker.png")

    manifest_data = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    anchors256 = manifest_data["source_runtime_files"]["west"]["anchors"]
    anchors512 = [(x * 2, y * 2) for x, y in anchors256]
    candidate_path = BATCH / "candidate_raw.png"
    cell_hashes = [
        {"phase": index + 1, "role": POSES[index], "sha256": digest(REFS / f"walk_west_k{index + 1:02d}_source.png")}
        for index in range(8)
    ]
    result_manifest = {
        "version": 2,
        "status": "source_only_review",
        "prompt": {"path": PROMPT_FILE.relative_to(ROOT).as_posix(), "sha256": digest(PROMPT_FILE)},
        "generation_metadata": json.loads(GENERATION_META.read_text(encoding="utf-8")) if GENERATION_META.exists() else None,
        "original_source": {"path": "assets/source/cat-worker-v1/locomotion/walk_west.png", "sha256": digest(WALK), "size": list(strip.size)},
        "source_cells": cell_hashes,
        "identity_source": {"path": "assets/source/cat-worker-v1/locomotion/idle_west.png", "sha256": digest(IDLE)},
        "role_map": {
            "west_facing": "character faces viewer-left; viewer-left is forward, viewer-right is trailing",
            "K1": "near/left (green) planted toward viewer-left; far/right (blue) trails viewer-right",
            "K4": "far/right (blue) raises knee; near/left (green) supports",
            "K5_target": "far/right (blue) plants toward viewer-left; near/left (green) trails viewer-right, toe lifted",
            "K6": "far/right (blue) remains support",
        },
        "reference_images": [
            {"path": (REFS / "walk_west_k01_source.png").relative_to(ROOT).as_posix(), "role": "K1 near/left contact reference", "sha256": digest(REFS / "walk_west_k01_source.png")},
            {"path": (REFS / "walk_west_k04_source.png").relative_to(ROOT).as_posix(), "role": "K4 far/right knee-up transition", "sha256": digest(REFS / "walk_west_k04_source.png")},
            {"path": (REFS / "walk_west_k05_source.png").relative_to(ROOT).as_posix(), "role": "Original K5 target to correct", "sha256": digest(REFS / "walk_west_k05_source.png")},
            {"path": (REFS / "walk_west_k06_source.png").relative_to(ROOT).as_posix(), "role": "K6 far/right weight-down continuation", "sha256": digest(REFS / "walk_west_k06_source.png")},
            {"path": (REFS / "west_k05_explicit_owner_map.png").relative_to(ROOT).as_posix(), "role": "Labeled viewer-left/right and near/far owner map", "sha256": digest(REFS / "west_k05_explicit_owner_map.png")},
        ],
        "review_outputs": {
            "source_contact_checker": (OUT / "west-source-owner-contact-checker.png").relative_to(ROOT).as_posix(),
            "runtime_anchors_256": anchors256,
            "fixed_scale_source512_to_64px": SCALE_512_TO_64,
            "key_duration_nominal_ms": 180,
            "key_duration_half_speed_ms": 360,
        },
    }
    if candidate_path.exists():
        raw = Image.open(candidate_path).convert("RGBA")
        target = cells[4]
        alpha_extrema = raw.getchannel("A").getextrema()
        raw_bbox = alpha16_bbox(raw)
        exterior_transparent = alpha_extrema[0] == 0 and raw_bbox != (0, 0, raw.width, raw.height)
        if exterior_transparent:
            review_frame, transform = rigid_review_frame(raw, target)
            preview_method = "uniform rigid source-to-target review alignment; no deformation"
        else:
            # This is a visualization of a rejected output only. Preserve the output canvas
            # with one uniform scale; do not infer a silhouette bbox or pretend the checker
            # background is transparency.
            if raw.width != raw.height:
                raise ValueError(f"Opaque candidate must be square for canvas-preserving review; got {raw.size}")
            scale = 512 / raw.width
            review_frame = raw.resize((512, 512), Image.Resampling.NEAREST)
            transform = {"uniform_scale_to_512_canvas": scale, "translation_xy": [0, 0], "method": "whole-output-canvas visual review only; opaque background retained"}
            preview_method = "uniform whole-canvas resize for rejected visual comparison; opaque background retained"
        normalized_path = OUT / ("candidate_k05_rigid_review_only.png" if exterior_transparent else "candidate_k05_uniform512_visual_only.png")
        review_frame.save(normalized_path)
        result_manifest["candidate"] = {
            "path": candidate_path.relative_to(ROOT).as_posix(),
            "sha256": digest(candidate_path),
            "alpha_edge_audit": alpha_audit(raw),
            "review_transform": transform,
            "review_method": preview_method,
            "review_only_path": normalized_path.relative_to(ROOT).as_posix(),
            "review_only_sha256": digest(normalized_path),
            "alpha_exterior_valid": exterior_transparent,
            "status": "review candidate" if exterior_transparent else "rejected: opaque exterior; no valid sprite alpha",
        }
        if not exterior_transparent:
            result_manifest["status"] = "source_only_review_with_rejected_candidate"
            result_manifest["candidate"]["rejection_reasons"] = [
                "No transparent exterior pixels; the generated checkerboard is baked into all pixels.",
                "At 64px game size the intended far/right support boot is still lifted while the near/left olive-trouser boot remains planted toward viewer-left.",
            ]
        candidate_cells = list(cells)
        candidate_cells[4] = review_frame
        # Full-cycle, actual 64px rendered height, fixed source scale and production anchors.
        cycle_contact = Image.new("RGB", (8 * TILE[0], 32 + 2 * (TILE[1] + 20)), (42, 44, 48))
        draw = ImageDraw.Draw(cycle_contact)
        for col, label in enumerate(POSES):
            draw.text((col * TILE[0] + 2, 6), f"K{col + 1} {label}", fill=(245, 240, 220), font=font)
        candidate_label = "candidate K5 (opaque raw visual only)" if not exterior_transparent else "candidate K5"
        for row, (row_label, row_frames) in enumerate((("source", cells), (candidate_label, candidate_cells))):
            y = 32 + row * (TILE[1] + 20)
            draw.text((4, y), row_label, fill=(245, 240, 220), font=font)
            y += 20
            for col, frame in enumerate(row_frames):
                layer = checker(TILE, cell=8)
                layer.alpha_composite(render64(frame, anchors512[col]))
                cycle_contact.paste(layer.convert("RGB"), (col * TILE[0], y))
                draw.rectangle((col * TILE[0], y, col * TILE[0] + TILE[0] - 1, y + TILE[1] - 1), outline=(90, 94, 100))
        cycle_path = OUT / "west-k05-full-cycle-64px-checker.png"
        cycle_contact.save(cycle_path)
        # Owner detail: K1, K4, original K5, candidate K5, K6 at common source canvas scale.
        owner_items = [("K1 source", cells[0]), ("K4 source", cells[3]), ("K5 original", cells[4]), ("K5 candidate raw visual only", review_frame), ("K6 source", cells[5])]
        detail = Image.new("RGB", (len(owner_items) * 512, 32 + 512), (42, 44, 48))
        draw = ImageDraw.Draw(detail)
        for col, (label, frame) in enumerate(owner_items):
            x = col * 512
            draw.text((x + 4, 6), label, fill=(245, 240, 220), font=font)
            layer = checker((512, 512))
            layer.alpha_composite(frame)
            detail.paste(layer.convert("RGB"), (x, 32))
        detail_path = OUT / "west-k05-labeled-owner-checker-contact.png"
        detail.save(detail_path)
        # Full sequence previews in place, at authored nominal and half speed.
        for delay, slug in ((180, "nominal"), (360, "half-speed")):
            rendered = []
            for index, frame in enumerate(candidate_cells):
                tile = checker((128, 104), cell=8)
                sprite = frame.resize((round(512 * SCALE_512_TO_64), round(512 * SCALE_512_TO_64)), Image.Resampling.NEAREST)
                tile.alpha_composite(sprite, (round(64 - anchors512[index][0] * SCALE_512_TO_64), round(84 - anchors512[index][1] * SCALE_512_TO_64)))
                rendered.append(tile.convert("RGB"))
            gif = OUT / f"west-k05-candidate-64px-{slug}.gif"
            rendered[0].save(gif, save_all=True, append_images=rendered[1:], duration=delay, loop=0, disposal=2)
        result_manifest["review_outputs"].update({
            "full_cycle_64px_checker": cycle_path.relative_to(ROOT).as_posix(),
            "labeled_owner_checker": detail_path.relative_to(ROOT).as_posix(),
            "candidate_64px_nominal_gif": (OUT / "west-k05-candidate-64px-nominal.gif").relative_to(ROOT).as_posix(),
            "candidate_64px_half_speed_gif": (OUT / "west-k05-candidate-64px-half-speed.gif").relative_to(ROOT).as_posix(),
        })
    manifest = BATCH / "hash-manifest.json"
    manifest.write_text(json.dumps(result_manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"batch": BATCH.as_posix(), "manifest": manifest.as_posix(), "candidate_present": candidate_path.exists(), "outputs": [p.name for p in OUT.iterdir()]}, indent=2))


if __name__ == "__main__":
    main()
