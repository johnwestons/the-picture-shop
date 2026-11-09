from __future__ import annotations

import hashlib
import json
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/animation-overhaul/luna-player/remaining-view-audit-v1"
RUNTIME = ROOT / "assets/generated/characters/rabbit-worker"
NORTH_V4 = ROOT / "assets/generated/player-walk-v4/walk_north.png"
FRAME = 512
DIRECTIONS = [
    ("north_current", "North current", NORTH_V4, RUNTIME / "idle_north.png"),
    ("northeast", "Northeast", RUNTIME / "walk_northeast.png", RUNTIME / "idle_northeast.png"),
    ("east", "East", RUNTIME / "walk.png", RUNTIME / "idle.png"),
    ("southeast", "Southeast", RUNTIME / "walk_southeast.png", RUNTIME / "idle_southeast.png"),
    ("south", "South", RUNTIME / "walk_south.png", RUNTIME / "idle_south.png"),
]
PHASES = [
    "left contact", "left weight-down", "right passing", "right knee-up",
    "right contact", "right weight-down", "left passing", "left knee-up",
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_bbox(image: Image.Image, threshold: int = 16):
    alpha = image.convert("RGBA").getchannel("A")
    return alpha.point(lambda v: 255 if v > threshold else 0).getbbox()


def is_orange(r: int, g: int, b: int, a: int) -> bool:
    return a > 64 and r > 130 and g > 45 and r > g * 1.20 and g > b * 1.10 and b < 125


def is_blue(r: int, g: int, b: int, a: int) -> bool:
    return a > 64 and b > 70 and b > r * 1.25 and g > 35 and b > g * 0.90


def metrics(image: Image.Image) -> dict:
    image = image.convert("RGBA")
    bbox = alpha_bbox(image)
    px = image.load()
    orange_rows: list[tuple[int, int, int]] = []
    blue_rows: list[tuple[int, int, int]] = []
    visible = dark = low_alpha = red = red_boundary = 0
    for y in range(image.height):
        xs_orange, xs_blue = [], []
        for x in range(image.width):
            r, g, b, a = px[x, y]
            if a:
                if a <= 16:
                    low_alpha += 1
                if a > 64:
                    visible += 1
                    if max(r, g, b) < 55:
                        dark += 1
                    if r > 150 and g < 90 and b < 110:
                        red += 1
                        outer = False
                        for yy in range(max(0, y - 1), min(image.height, y + 2)):
                            for xx in range(max(0, x - 1), min(image.width, x + 2)):
                                if px[xx, yy][3] <= 16:
                                    outer = True
                        red_boundary += int(outer)
            if 95 <= y <= 260 and is_orange(r, g, b, a):
                xs_orange.append(x)
            if 220 <= y <= 390 and is_blue(r, g, b, a):
                xs_blue.append(x)
        if xs_orange:
            orange_rows.append((y, min(xs_orange), max(xs_orange) + 1))
        if xs_blue:
            blue_rows.append((y, min(xs_blue), max(xs_blue) + 1))
    head_row = max(orange_rows, key=lambda item: item[2] - item[1]) if orange_rows else None
    blue_widths = [x1 - x0 for _, x0, x1 in blue_rows]
    blue_median = median(blue_widths) if blue_widths else None
    blue_max = max(blue_rows, key=lambda item: item[2] - item[1]) if blue_rows else None
    return {
        "bbox_alpha_gt16_xyxy": list(bbox) if bbox else None,
        "visible_height_px": bbox[3] - bbox[1] if bbox else 0,
        "visible_width_px": bbox[2] - bbox[0] if bbox else 0,
        "baseline_y_exclusive": bbox[3] if bbox else None,
        "horizontal_bbox_center_x": (bbox[0] + bbox[2]) / 2 if bbox else None,
        "head_orange_max_row_width_px": (head_row[2] - head_row[1]) if head_row else None,
        "head_orange_max_row_y": head_row[0] if head_row else None,
        "head_orange_center_x": (head_row[1] + head_row[2]) / 2 if head_row else None,
        "torso_blue_median_row_width_px": blue_median,
        "torso_blue_max_row_width_px": (blue_max[2] - blue_max[1]) if blue_max else None,
        "torso_blue_max_row_y": blue_max[0] if blue_max else None,
        "dark_pixel_share_of_visible_alpha64_percent": round(100 * dark / visible, 3) if visible else 0,
        "red_dominant_pixels_alpha64": red,
        "red_dominant_pixels_at_silhouette_alpha64_proxy": red_boundary,
        "low_alpha_pixels_1_to_16": low_alpha,
        "visible_pixels_alpha64": visible,
        "frame_edge_clearance_px": min(bbox[0], bbox[1], FRAME - bbox[2], FRAME - bbox[3]) if bbox else None,
    }


def resize64(image: Image.Image) -> Image.Image:
    return image.convert("RGBa").resize((64, 64), Image.Resampling.LANCZOS).convert("RGBA")


def white_canvas(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, (255, 255, 255, 255))


def load_strip(path: Path, count: int) -> list[Image.Image]:
    strip = Image.open(path).convert("RGBA")
    if strip.size != (FRAME * count, FRAME):
        raise SystemExit(f"Unexpected strip size for {path}: {strip.size}")
    return [strip.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME)) for i in range(count)]


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Audit rabbit-worker walk scale and phase presentation across authored views.")
    parser.add_argument("--north-strip", type=Path, default=NORTH_V4)
    parser.add_argument("--output-dir", type=Path, default=OUT)
    args = parser.parse_args()
    north_strip = args.north_strip if args.north_strip.is_absolute() else ROOT / args.north_strip
    out_dir = args.output_dir if args.output_dir.is_absolute() else ROOT / args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    directions = [
        (key, label,
         north_strip if key == "north_current" else walk_path, idle_path)
        for key, label, walk_path, idle_path in DIRECTIONS
    ]
    walk: dict[str, list[Image.Image]] = {}
    idle: dict[str, list[Image.Image]] = {}
    view_audit = []
    for key, label, walk_path, idle_path in directions:
        walk[key] = load_strip(walk_path, 8)
        idle[key] = load_strip(idle_path, 2)
        view_audit.append({
            "key": key,
            "label": label,
            "walk_path": walk_path.relative_to(ROOT).as_posix(),
            "walk_sha256": sha(walk_path),
            "idle_path": idle_path.relative_to(ROOT).as_posix(),
            "idle_sha256": sha(idle_path),
            "walk_frames": [{"phase": i + 1, "role": PHASES[i], **metrics(frame)} for i, frame in enumerate(walk[key])],
            "idle_frames": [{"pose": i + 1, **metrics(frame)} for i, frame in enumerate(idle[key])],
        })

    font = ImageFont.load_default()
    walk_contact = white_canvas((FRAME * 8, 5 * (FRAME + 26)))
    draw = ImageDraw.Draw(walk_contact)
    for row, (key, label, _, _) in enumerate(directions):
        y = row * (FRAME + 26)
        draw.text((4, y + 2), f"{label} | 8 canonical phases", fill=(0, 0, 0), font=font)
        for col, frame in enumerate(walk[key]):
            x = col * FRAME
            walk_contact.alpha_composite(frame, (x, y + 26))
            draw.text((x + 4, y + 27), f"{col + 1}: {PHASES[col]}", fill=(0, 0, 0), font=font)
    walk_contact_path = out_dir / "five-view-walk-phase-contact-512px.png"
    walk_contact.convert("RGB").save(walk_contact_path)

    small_contact = white_canvas((8 * 64, 5 * 82))
    draw = ImageDraw.Draw(small_contact)
    for row, (key, label, _, _) in enumerate(directions):
        y = row * 82
        draw.text((2, y + 1), label, fill=(0, 0, 0), font=font)
        for col, frame in enumerate(walk[key]):
            small_contact.alpha_composite(resize64(frame), (col * 64, y + 18))
            draw.text((col * 64 + 2, y + 18), str(col + 1), fill=(0, 0, 0), font=font)
    small_contact_path = out_dir / "five-view-walk-phase-contact-64px.png"
    small_contact.convert("RGB").save(small_contact_path)

    idle_contact = white_canvas((5 * 64, 4 * 82))
    draw = ImageDraw.Draw(idle_contact)
    for col, (key, label, _, _) in enumerate(directions):
        draw.text((col * 64 + 1, 0), label[:9], fill=(0, 0, 0), font=font)
        for row, frame in enumerate([idle[key][0], idle[key][1], walk[key][0], walk[key][4]]):
            y = row * 82 + 18
            idle_contact.alpha_composite(resize64(frame), (col * 64, y))
            row_label = ["idle 1", "idle 2", "walk 1", "walk 5"][row]
            draw.text((col * 64 + 1, y + 1), row_label, fill=(0, 0, 0), font=font)
    idle_contact_path = out_dir / "idle-and-contact-crossview-64px.png"
    idle_contact.convert("RGB").save(idle_contact_path)

    pass_contact = white_canvas((5 * 64, 2 * 82))
    draw = ImageDraw.Draw(pass_contact)
    for col, (key, label, _, _) in enumerate(directions):
        draw.text((col * 64 + 1, 0), label[:9], fill=(0, 0, 0), font=font)
        for row, phase_index in enumerate([2, 6]):
            y = row * 82 + 18
            pass_contact.alpha_composite(resize64(walk[key][phase_index]), (col * 64, y))
            draw.text((col * 64 + 1, y + 1), f"p{phase_index+1}", fill=(0, 0, 0), font=font)
    pass_contact_path = out_dir / "passing-phase-3-and-7-64px.png"
    pass_contact.convert("RGB").save(pass_contact_path)

    key_contact = white_canvas((4 * FRAME, 5 * (FRAME + 24)))
    key_draw = ImageDraw.Draw(key_contact)
    foot_contact = white_canvas((4 * FRAME, 5 * (220 + 24)))
    foot_draw = ImageDraw.Draw(foot_contact)
    key_indices = [0, 2, 4, 6]
    for row, (key, label, _, _) in enumerate(directions):
        y = row * (FRAME + 24)
        foot_y = row * (220 + 24)
        key_draw.text((4, y + 2), f"{label} | contact/pass owners", fill=(0, 0, 0), font=font)
        foot_draw.text((4, foot_y + 2), f"{label} | lower-body owners", fill=(0, 0, 0), font=font)
        for col, phase_index in enumerate(key_indices):
            x = col * FRAME
            key_contact.alpha_composite(walk[key][phase_index], (x, y + 24))
            key_draw.text((x + 4, y + 26), f"{phase_index + 1}: {PHASES[phase_index]}", fill=(0, 0, 0), font=font)
            feet = walk[key][phase_index].crop((0, 292, FRAME, FRAME))
            foot_contact.alpha_composite(feet, (x, foot_y + 24))
            foot_draw.text((x + 4, foot_y + 25), f"p{phase_index + 1}", fill=(0, 0, 0), font=font)
    key_contact_path = out_dir / "contact-and-pass-key-phases-512px.png"
    foot_contact_path = out_dir / "lower-body-contact-pass-owners-512px.png"
    key_contact.convert("RGB").save(key_contact_path)
    foot_contact.convert("RGB").save(foot_contact_path)

    gif_paths = []
    for key, label, _, _ in directions:
        frames = [resize64(frame).convert("RGB") for frame in walk[key]]
        gif_path = out_dir / f"walk-{key}-64px-130ms.gif"
        frames[0].save(gif_path, save_all=True, append_images=frames[1:], duration=130, loop=0, disposal=2, optimize=False)
        gif_paths.append(gif_path)

    north_current = view_audit[0]
    old_views = view_audit[1:]
    north_heights = [x["visible_height_px"] for x in north_current["walk_frames"]]
    other_height_ranges = {x["key"]: [min(f["visible_height_px"] for f in x["walk_frames"]), max(f["visible_height_px"] for f in x["walk_frames"])] for x in old_views}
    outline_medians = {x["key"]: round(median(f["dark_pixel_share_of_visible_alpha64_percent"] for f in x["walk_frames"]), 3) for x in view_audit}
    idle_heights = {x["key"]: [f["visible_height_px"] for f in x["idle_frames"]] for x in view_audit}
    outputs = [walk_contact_path, small_contact_path, idle_contact_path, pass_contact_path, key_contact_path, foot_contact_path, *gif_paths]
    audit = {
        "title": "Rabbit-worker five-view gait and scale audit; review only",
        "scope": f"{north_current['label']} plus the four other authored walks (NE, E, SE, S) and matching two-frame idles. Native 512px and 64px display-scale review; no runtime/spec files altered.",
        "north_strip": north_current["walk_path"],
        "phase_roles_from_spec": PHASES,
        "views": view_audit,
        "north_findings": {
            "visible_height_range_px": [min(north_heights), max(north_heights)],
            "phase1_to_phase8_bboxes": [frame["bbox_alpha_gt16_xyxy"] for frame in north_current["walk_frames"]],
            "phase1_to_phase8_baselines": [frame["baseline_y_exclusive"] for frame in north_current["walk_frames"]],
            "phase1_to_phase8_dark_shares_percent": [frame["dark_pixel_share_of_visible_alpha64_percent"] for frame in north_current["walk_frames"]],
            "phase1_to_phase8_red_boundary_proxy_counts": [frame["red_dominant_pixels_at_silhouette_alpha64_proxy"] for frame in north_current["walk_frames"]],
            "phase3_and_phase7_contact_sheet_path": pass_contact_path.relative_to(ROOT).as_posix(),
            "note": "Review phase 1 vs 5 contacts and phase 3 vs 7 passing owners at both 512px and 64px. Automated alpha-bound and color proxies do not prove foot ownership.",
        },
        "cross_view_summary": {
            "north_height_range_px": [min(north_heights), max(north_heights)],
            "other_walk_height_ranges_px": other_height_ranges,
            "idle_height_by_view_px": idle_heights,
            "dark_pixel_share_medians_percent": outline_medians,
            "outline_proxy_note": "Dark-pixel share includes internal detail and is only a relative weight proxy, not literal stroke width.",
        },
        "contact_sheets": {
            "walk_native_512": walk_contact_path.relative_to(ROOT).as_posix(),
            "walk_game_scale_64": small_contact_path.relative_to(ROOT).as_posix(),
            "idle_and_contacts_game_scale_64": idle_contact_path.relative_to(ROOT).as_posix(),
            "passing_phases_game_scale_64": pass_contact_path.relative_to(ROOT).as_posix(),
            "contacts_and_pass_owners_native_512": key_contact_path.relative_to(ROOT).as_posix(),
            "lower_body_owners_native_512": foot_contact_path.relative_to(ROOT).as_posix(),
        },
        "timed_previews": [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p), "frame_count": 8, "frame_size_px": [64, 64], "duration_ms": 130} for p in gif_paths],
        "source_hashes_sha256": {entry["walk_path"]: entry["walk_sha256"] for entry in view_audit} | {entry["idle_path"]: entry["idle_sha256"] for entry in view_audit},
        "output_hashes_sha256": {p.relative_to(ROOT).as_posix(): sha(p) for p in outputs},
        "visual_review": {},
        "decision": "Pending human phase-role visual review of the staged contacts; no correction generated in this audit builder.",
    }
    audit_path = out_dir / "rabbit-worker-five-view-gait-audit.json"
    audit_path.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print(json.dumps({
        "north_height_range": audit["north_findings"]["visible_height_range_px"],
        "view_height_ranges": audit["cross_view_summary"]["other_walk_height_ranges_px"],
        "outline_medians": outline_medians,
        "outputs": audit["output_hashes_sha256"],
        "audit_path": audit_path.relative_to(ROOT).as_posix(),
    }, indent=2))


if __name__ == "__main__":
    main()
