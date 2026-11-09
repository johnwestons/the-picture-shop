"""Audit weak-alpha residues, body/vest dimensions, and manual support soles in frozen V4.

Reads the immutable V4 raw master and selection; writes only a bounded review
package (JSON and contact-crop image) beside the staged proposal.
"""
from __future__ import annotations

import hashlib
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
SOURCE = ROOT / "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/canonical-8phase-v4-empty-gap-registration"
OUT_SOURCE = Path(__file__).resolve().parent
OUT = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/v4-foot-contact-audit"
RAW_PATH = SOURCE / "field-mouse-technician-west-canonical-8phase-v3-master-raw.png"
SELECTION_PATH = SOURCE / "selection.json"
STRIP_PATH = SOURCE / "field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png"
IDLE_PATH = ROOT / "assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png"
LANDMARK_PROTOCOL_PATH = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/identity-continuity/build_identity_continuity.py"
EXPECTED_RAW = "5465fe188fea59a8d9484f27b738a9078dcb77eb0b0724b96ce53a41dbce5ef5"
EXPECTED_SELECTION = "4e442b12baedaef0289c06d62b37b8b986ea7debdaff61e942707bca37f8fedb"
EXPECTED_STRIP = "55cb2cd186b169dc9ae5acc6814b40a3ca6ad6a7207c8456b9a1e7244b21992c"
EXPECTED_IDLE = "886efc1ad1bf57bedb3a1b98927b82135281b9d53599f080b592e37a979a0f66"
FRAME_ROLES = [
    "K1 near/pocketed lead contact; far/plain leg trails",
    "K2 near/pocketed weight-down; far/plain heel releases",
    "K3 far/plain compact pass; near/pocketed supports",
    "K4 far/plain knee-up; near/pocketed supports",
    "K5 far/plain lead contact; near/pocketed leg trails",
    "K6 far/plain weight-down; near/pocketed heel releases",
    "K7 near/pocketed compact pass; far/plain supports",
    "K8 near/pocketed knee-up; far/plain supports",
]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def components8(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    ys, xs = np.where(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if seen[sy, sx]:
            continue
        seen[sy, sx] = True
        todo = deque([(sy, sx)])
        group = []
        while todo:
            y, x = todo.popleft()
            group.append((y, x))
            for ny in range(max(0, y - 1), min(h, y + 2)):
                for nx in range(max(0, x - 1), min(w, x + 2)):
                    if mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        todo.append((ny, nx))
        found.append(group)
    return found


def nearest_strong_distance(points: np.ndarray, strong: np.ndarray) -> float | None:
    pyx = np.argwhere(points)
    syx = np.argwhere(strong)
    if not len(pyx) or not len(syx):
        return None
    # Chunk to cap temporary memory; return distance between pixel centers.
    best2 = None
    for start in range(0, len(pyx), 16):
        block = pyx[start:start + 16].astype(np.int32)
        delta = block[:, None, :] - syx[None, :, :]
        d2 = np.einsum("ijk,ijk->ij", delta, delta)
        local = int(d2.min())
        best2 = local if best2 is None else min(best2, local)
    return float(best2 ** 0.5)


def landmarks(frame: Image.Image) -> dict:
    """Same alpha/head/vest/trouser proxy used by build_identity_continuity.py."""
    alpha = np.asarray(frame.getchannel("A"))
    ys, xs = np.where(alpha >= 16)
    left, top, right, bottom = int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)
    height = bottom - top
    head_rows = alpha[top:top + round(height * 0.43), :] > 16
    hy, hx = np.where(head_rows)
    head_box = [int(hx.min()), int(top + hy.min()), int(hx.max() + 1), int(top + hy.max() + 1)]
    centers = []
    for y in range(top + round(height * 0.32), top + round(height * 0.50)):
        row_x = np.flatnonzero(alpha[y, left:right] >= 128)
        if len(row_x):
            centers.append(left + (int(row_x.min()) + int(row_x.max()) + 1) / 2)
    torso_axis = float(np.median(centers))
    rgb = np.asarray(frame.convert("RGB"), dtype=np.int16)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    y0, y1 = top + round(height * 0.30), top + round(height * 0.61)
    orange = (alpha[y0:y1, :] > 16) & (r[y0:y1, :] >= 170) & (g[y0:y1, :] >= 45) & (g[y0:y1, :] <= 185) & (b[y0:y1, :] <= 125) & ((r[y0:y1, :] - g[y0:y1, :]) >= 45)
    oy, ox = np.where(orange)
    vest_axis = float(np.median(ox))
    vx0, vx1 = max(0, round(vest_axis - 22)), min(frame.width, round(vest_axis + 23))
    central = (alpha[y0:y1, vx0:vx1] > 16) & (r[y0:y1, vx0:vx1] >= 170) & (g[y0:y1, vx0:vx1] >= 45) & (g[y0:y1, vx0:vx1] <= 185) & (b[y0:y1, vx0:vx1] <= 125) & ((r[y0:y1, vx0:vx1] - g[y0:y1, vx0:vx1]) >= 45)
    vrows = np.flatnonzero(central.sum(axis=1) >= 3)
    vest_top, vest_bottom = y0 + int(vrows[0]), y0 + int(vrows[-1])
    navy = (alpha > 16) & (r < 130) & (g < 150) & (b < 205) & (b > r * 1.08) & (b > g * 0.86)
    nx0, nx1 = max(0, round(torso_axis - 20)), min(frame.width, round(torso_axis + 21))
    lower = navy[max(vest_bottom, 0):bottom, nx0:nx1]
    rows = np.flatnonzero(lower.sum(axis=1) >= 2)
    pants_top = max(vest_bottom, 0) + int(rows[0]) if len(rows) else None
    return {
        "body_alpha_ge16_bbox_xyxy": [left, top, right, bottom],
        "body_height_px": height,
        "head_bbox_proxy_xyxy": head_box,
        "head_width_px": head_box[2] - head_box[0],
        "torso_axis_x_px": round(torso_axis, 3),
        "central_vest_orange_y_span_inclusive_px": [vest_top, vest_bottom],
        "central_vest_orange_height_px": vest_bottom - vest_top + 1,
        "central_navy_trouser_onset_y_px_proxy": pants_top,
        "trouser_onset_to_ground_px_proxy": bottom - 1 - pants_top if pants_top is not None else None,
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    if sha(RAW_PATH) != EXPECTED_RAW or sha(SELECTION_PATH) != EXPECTED_SELECTION or sha(STRIP_PATH) != EXPECTED_STRIP or sha(IDLE_PATH) != EXPECTED_IDLE:
        raise SystemExit("Frozen V4 input hash mismatch; refusing to audit changed inputs")
    selection = json.loads(SELECTION_PATH.read_text(encoding="utf-8"))
    raw = np.asarray(Image.open(RAW_PATH).convert("RGBA"))
    strip_img = Image.open(STRIP_PATH).convert("RGBA")
    strip = np.asarray(strip_img)

    frames = []
    all_omitted = 0
    for index, record in enumerate(selection["frames"]):
        x0, y0, x1, y1 = record["raw_crop_bounds_xyxy_exclusive"]
        lx0, ly0, lx1, ly1 = record["render_content_bounds_in_source_crop_xyxy_exclusive"]
        crop_alpha = raw[y0:y1, x0:x1, 3]
        omitted = crop_alpha > 0
        omitted[ly0:ly1, lx0:lx1] = False
        strong = crop_alpha >= 16
        groups = components8(omitted)
        components = []
        for group in groups:
            local = np.zeros_like(omitted)
            for y, x in group:
                local[y, x] = True
            gy = np.array([p[0] + y0 for p in group], dtype=np.int32)
            gx = np.array([p[1] + x0 for p in group], dtype=np.int32)
            values = crop_alpha[local]
            # Perceptual/geometry relation: this is the nearest source alpha>=16 pixel.
            dist = nearest_strong_distance(local, strong)
            components.append({
                "count": len(group),
                "alpha_min_max": [int(values.min()), int(values.max())],
                "bbox_crop_xyxy_exclusive": [int(min(p[1] for p in group)), int(min(p[0] for p in group)), int(max(p[1] for p in group) + 1), int(max(p[0] for p in group) + 1)],
                "bbox_global_xyxy_exclusive": [int(gx.min()), int(gy.min()), int(gx.max() + 1), int(gy.max() + 1)],
                "nearest_alpha_ge16_pixel_distance_px": dist,
            })
        all_omitted += int(omitted.sum())
        cell = strip[:, index * 256:(index + 1) * 256]
        a = cell[:, :, 3]
        # Per-frame V4 rendered body measurement, held at the frozen 27/56 atlas scale.
        yy, xx = np.where(a >= 16)
        measure = landmarks(Image.fromarray(cell, "RGBA"))
        frames.append({
            "phase": index + 1,
            "role": FRAME_ROLES[index],
            "omitted_weak_alpha_pixels": int(omitted.sum()),
            "omitted_weak_alpha_component_count": len(components),
            "omitted_weak_alpha_components": components,
            "fixed_27_over_56_scale_landmarks": measure,
        })

    # Support sole anchors manually interpreted on registered-cell crops (pixel centers).
    manual_anchors = [
        {"phase": 1, "support_leg": "near/pocketed", "contact_x_px": 103.5, "contact_y_px": 229, "lowest_alpha_ge16_row": 229, "sole_run_x_half_open": [98, 109], "roi_xyxy": [90, 226, 112, 230], "confidence": "medium; near lead outsole clear, trailing far shoe also touches ground"},
        {"phase": 2, "support_leg": "near/pocketed", "contact_x_px": 112.5, "contact_y_px": 228, "lowest_alpha_ge16_row": 228, "sole_run_x_half_open": [98, 127], "roi_xyxy": [96, 225, 130, 229], "confidence": "high; near planted sole clear, far heel is raised"},
        {"phase": 3, "support_leg": "near/pocketed", "contact_x_px": 121.5, "contact_y_px": 229, "lowest_alpha_ge16_row": 229, "sole_run_x_half_open": [108, 135], "roi_xyxy": [104, 226, 137, 230], "confidence": "medium; sole is partially overdrawn/segmented by alpha gaps"},
        {"phase": 4, "support_leg": "near/pocketed", "contact_x_px": 130.5, "contact_y_px": 229, "lowest_alpha_ge16_row": 229, "sole_run_x_half_open": [118, 143], "roi_xyxy": [112, 226, 145, 230], "confidence": "high; near boot planted, lifted far boot is separate to screen-left"},
        {"phase": 5, "support_leg": "far/plain", "contact_x_px": 105.5, "contact_y_px": 229, "lowest_alpha_ge16_row": 229, "sole_run_x_half_open": [103, 108], "roi_xyxy": [95, 226, 114, 230], "confidence": "low; contact row is only six alpha>=16 pixels and has low outsole extent"},
        {"phase": 6, "support_leg": "far/plain", "contact_x_px": 118.5, "contact_y_px": 228, "lowest_alpha_ge16_row": 228, "sole_run_x_half_open": [110, 127], "roi_xyxy": [108, 225, 131, 229], "confidence": "medium; far planted boot visible, near heel raised"},
        {"phase": 7, "support_leg": "far/plain", "contact_x_px": 141.5, "contact_y_px": 228, "lowest_alpha_ge16_row": 228, "sole_run_x_half_open": [134, 149], "roi_xyxy": [132, 225, 153, 229], "confidence": "low; crossing near boot overlaps the near-sole row; selected right horizontal outsole as far support"},
        {"phase": 8, "support_leg": "far/plain", "contact_x_px": 132.5, "contact_y_px": 228, "lowest_alpha_ge16_row": 228, "sole_run_x_half_open": [117, 148], "roi_xyxy": [115, 225, 150, 229], "confidence": "medium; far horizontal support sole is clear, lifted near boot separate to screen-left"},
    ]
    for anchor in manual_anchors:
        i = anchor["phase"] - 1
        cell = strip[:, i * 256:(i + 1) * 256]
        x0, y0, x1, y1 = anchor["roi_xyxy"]
        roi_alpha = cell[y0:y1, x0:x1, 3]
        rys, rxs = np.where(roi_alpha >= 16)
        frame_rec = selection["frames"][i]
        cbx0, cby0, cbx1, cby1 = frame_rec["raw_crop_bounds_xyxy_exclusive"]
        rb_x0, rb_y0, _, _ = frame_rec["render_content_bounds_in_source_crop_xyxy_exclusive"]
        paste_x, paste_y = frame_rec["paste_offset_xy_px"]
        scale = selection["registration"]["global_scale"]
        src_local_x0 = rb_x0 + (x0 - paste_x) / scale
        src_local_y0 = rb_y0 + (y0 - paste_y) / scale
        src_local_x1 = rb_x0 + (x1 - paste_x) / scale
        src_local_y1 = rb_y0 + (y1 - paste_y) / scale
        src_bounds = [int(np.floor(src_local_x0)), int(np.floor(src_local_y0)), int(np.ceil(src_local_x1)), int(np.ceil(src_local_y1))]
        anchor["registered_roi_alpha_ge16_count"] = int((roi_alpha >= 16).sum())
        anchor["source_crop_bounds_xyxy_floor_ceil"] = src_bounds
        anchor["source_global_bounds_xyxy_floor_ceil"] = [cbx0 + src_bounds[0], cby0 + src_bounds[1], cbx0 + src_bounds[2], cby0 + src_bounds[3]]
        raw_roi = raw[cby0 + src_bounds[1]:cby0 + src_bounds[3], cbx0 + src_bounds[0]:cbx0 + src_bounds[2], 3]
        sy, sx = np.where(raw_roi >= 16)
        anchor["raw_source_alpha_ge16_bbox_in_roi_xyxy"] = [int(sx.min() + src_bounds[0]), int(sy.min() + src_bounds[1]), int(sx.max() + 1 + src_bounds[0]), int(sy.max() + 1 + src_bounds[1])] if len(sx) else None
        if anchor["raw_source_alpha_ge16_bbox_in_roi_xyxy"] is not None:
            rx0, ry0, rx1, ry1 = anchor["raw_source_alpha_ge16_bbox_in_roi_xyxy"]
            anchor["raw_source_alpha_ge16_bbox_global_xyxy"] = [cbx0 + rx0, cby0 + ry0, cbx0 + rx1, cby0 + ry1]
        anchor["source_to_registered_contact_formula"] = "cell px = round(paste offset + (raw crop px - render-content crop origin) * 27/56)"

    # A 4x2 review board: top half shows each whole frame at 1x with a 16px grid;
    # bottom half enlarges only the candidate support-foot ROI for manual sole marking.
    canvas = Image.new("RGB", (4 * 360, 2 * 480), (29, 33, 38))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    for i, anchor in enumerate(manual_anchors):
        cx, cy = (i % 4) * 360, (i // 4) * 480
        draw.text((cx + 8, cy + 4), f"K{i+1} {anchor['support_leg']} x={anchor['contact_x_px']:.1f} y={anchor['contact_y_px']} | {anchor['confidence'].split(';')[0]}", fill=(255, 224, 128), font=font)
        cell = strip_img.crop((i * 256, 0, (i + 1) * 256, 256))
        cell_rgb = Image.new("RGB", (256, 256), (29, 33, 38))
        cell_rgb.paste(cell, mask=cell.getchannel("A"))
        # Whole pose display, with coordinate grid and origin ticks.
        whole = cell_rgb.resize((256, 256), Image.Resampling.NEAREST)
        whole_draw = ImageDraw.Draw(whole)
        for gx in range(0, 257, 16):
            whole_draw.line((gx, 0, gx, 255), fill=(75, 82, 90), width=1)
            if gx < 256:
                whole_draw.text((gx + 1, 1), str(gx), fill=(195, 203, 211), font=font)
        for gy in range(0, 257, 16):
            whole_draw.line((0, gy, 255, gy), fill=(75, 82, 90), width=1)
        ax, ay = anchor["contact_x_px"], anchor["contact_y_px"]
        whole_draw.ellipse((round(ax) - 3, ay - 3, round(ax) + 3, ay + 3), outline=(65, 255, 245), width=2)
        canvas.paste(whole, (cx + 12, cy + 28))
        # Crop around candidate support foot; no resizing applied to the source frame itself.
        rx0, ry0, rx1, ry1 = anchor["roi_xyxy"]
        foot = cell_rgb.crop((rx0, ry0, rx1, ry1)).resize((4 * (rx1 - rx0), 4 * (ry1 - ry0)), Image.Resampling.NEAREST)
        fd = ImageDraw.Draw(foot)
        for gx in range(0, foot.width + 1, 16 * 4):
            fd.line((gx, 0, gx, foot.height), fill=(100, 110, 120), width=1)
        for gy in range(0, foot.height + 1, 16 * 4):
            fd.line((0, gy, foot.width, gy), fill=(100, 110, 120), width=1)
        canvas.paste(foot, (cx + 12, cy + 292))
        draw.text((cx + 16, cy + 276), f"support ROI x={rx0}:{rx1}, y={ry0}:{ry1} | enlarged 4x", fill=(200, 210, 220), font=font)

    contact_path = OUT / "field-mouse-west-v4-support-foot-ROIs.png"
    canvas.save(contact_path)
    # Separate close-up strip with cell-coordinate tick labels and a ground line.
    foot_canvas = Image.new("RGB", (4 * 500, 2 * 205), (29, 33, 38))
    foot_draw = ImageDraw.Draw(foot_canvas)
    for i, anchor in enumerate(manual_anchors):
        cx, cy = (i % 4) * 500, (i // 4) * 205
        foot_draw.text((cx + 8, cy + 4), f"K{i+1} {anchor['support_leg']} candidate | cell pixels", fill=(255, 224, 128), font=font)
        cell = strip_img.crop((i * 256, 0, (i + 1) * 256, 256))
        rgb_cell = Image.new("RGB", (256, 256), (29, 33, 38))
        rgb_cell.paste(cell, mask=cell.getchannel("A"))
        x0, y0, x1, y1 = 55, 205, 175, 235
        zoom = rgb_cell.crop((x0, y0, x1, y1)).resize((480, 120), Image.Resampling.NEAREST)
        zd = ImageDraw.Draw(zoom)
        for local_x in range(0, 121, 4):
            zd.line((local_x * 4, 0, local_x * 4, 119), fill=(83, 94, 106), width=1)
            if local_x % 8 == 0 and local_x < 120:
                zd.text((local_x * 4 + 1, 1), str(x0 + local_x), fill=(230, 235, 240), font=font)
        for local_y in range(0, 31, 4):
            yy = local_y * 4
            color = (255, 100, 100) if y0 + local_y == 229 else (83, 94, 106)
            zd.line((0, yy, 479, yy), fill=color, width=2 if y0 + local_y == 229 else 1)
        marker_x = round((anchor["contact_x_px"] - x0) * 4)
        marker_y = round((anchor["contact_y_px"] - y0) * 4)
        zd.line((marker_x, 0, marker_x, 119), fill=(65, 255, 245), width=2)
        zd.ellipse((marker_x - 4, marker_y - 4, marker_x + 4, marker_y + 4), outline=(65, 255, 245), width=2)
        foot_canvas.paste(zoom, (cx + 8, cy + 26))
        ImageDraw.Draw(foot_canvas).text((cx + 8, cy + 151), f"cyan = contact x{anchor['contact_x_px']:.1f} at y{anchor['contact_y_px']}; red line = ground y229", fill=(200, 210, 220), font=font)
    foot_detail_path = OUT / "field-mouse-west-v4-support-sole-coordinate-detail.png"
    foot_canvas.save(foot_detail_path)
    idle_strip = Image.open(IDLE_PATH).convert("RGBA")
    idle_measures = [landmarks(idle_strip.crop((i * 256, 0, (i + 1) * 256, 256))) for i in range(2)]
    helper_hash = sha(LANDMARK_PROTOCOL_PATH)
    residue_alpha_hist = {}
    for phase in frames:
        for comp in phase["omitted_weak_alpha_components"]:
            lo, hi = comp["alpha_min_max"]
            residue_alpha_hist[f"{lo}..{hi}"] = residue_alpha_hist.get(f"{lo}..{hi}", 0) + comp["count"]

    # Raw-source context overlay: each frame's all pixels below alpha16 outside
    # the frozen render crop are magenta; no source pixels are altered.
    trace = Image.new("RGB", (1774, 2 * 460), (29, 33, 38))
    td = ImageDraw.Draw(trace)
    for i, rec in enumerate(selection["frames"]):
        x0, y0, x1, y1 = rec["raw_crop_bounds_xyxy_exclusive"]
        raw_crop = Image.fromarray(raw[y0:y1, x0:x1]).convert("RGBA")
        raw_alpha = np.asarray(raw_crop.getchannel("A"))
        bx0, by0, bx1, by1 = rec["render_content_bounds_in_source_crop_xyxy_exclusive"]
        residue = (raw_alpha > 0) & (raw_alpha < 16)
        residue[by0:by1, bx0:bx1] = False
        bg = Image.new("RGBA", raw_crop.size, (29, 33, 38, 255))
        bg.alpha_composite(raw_crop)
        pix = np.asarray(bg.convert("RGB")).copy()
        pix[residue] = (255, 0, 255)
        panel = Image.fromarray(pix, "RGB")
        panel.thumbnail((443, 430), Image.Resampling.NEAREST)
        px, py = (i % 4) * 443, (i // 4) * 460
        trace.paste(panel, (px, py + 22))
        td.text((px + 5, py + 4), f"K{i+1}: magenta=alpha1..15 omitted outside render crop; raw {x0},{y0}..{x1},{y1}", fill=(255, 224, 128))
    trace_path = OUT / "field-mouse-west-v4-weak-alpha-source-trace.png"
    trace.save(trace_path)

    result = {
        "status": "bounded QA only; frozen V4 source and registered strips unchanged; no runtime promotion",
        "inputs": {
            "raw_master": {"path": str(RAW_PATH.relative_to(ROOT)), "sha256": sha(RAW_PATH)},
            "selection": {"path": str(SELECTION_PATH.relative_to(ROOT)), "sha256": sha(SELECTION_PATH)},
            "registered_runtime_strip": {"path": str(STRIP_PATH.relative_to(ROOT)), "sha256": sha(STRIP_PATH)},
            "approved_idle_west": {"path": str(IDLE_PATH.relative_to(ROOT)), "sha256": sha(IDLE_PATH)},
            "landmark_method_reference": {"path": str(LANDMARK_PROTOCOL_PATH.relative_to(ROOT)), "sha256": helper_hash, "note": "The audit duplicates the same landmark equations so it remains self-contained; protocol source recorded here for comparison."},
        },
        "scale": {"global_master_scale": "27/56", "fixed_world_display_scale": "64/192 = 1/3", "no_resizing_per_phase": True},
        "weak_alpha": {
            "threshold": "source alpha 1..15",
            "outside_final_registered_render_bounds_count": all_omitted,
            "source_alpha_histogram": residue_alpha_hist,
            "component_location_summary": "Components are source-local coordinate boxes with distance to nearest alpha>=16 pixel in each frame. Every omitted pixel is alpha 1, never attached to the alpha>=16 silhouette; K5/K7 have some tail-side/margin-adjacent flecks, but their alpha=1 is 1/255 opacity and their nearest alpha>=16 gaps are 32.8px (K5) and 9.0px (K7) in raw source units. No clipped paw/body/ear was found in this class.",
            "visual_impact_at_fixed_64_world_scale": "At 27/56 source-to-cell scale followed by 64/256 display scale, each source pixel covers about 0.12 output pixels. Alpha 1/255 marks cannot add a readable limb, ear, or tail contour. They appear only as sparse magenta audit pixels when deliberately recolored; original low-opacity pixels are effectively imperceptible.",
            "frames": frames,
        },
        "fixed_scale_geometry": {
            "walk_frames": [f["fixed_27_over_56_scale_landmarks"] for f in frames],
            "idle_west_frames": idle_measures,
            "fixed_world_display_scale": "64/192 = 1/3 source cell px to world px",
            "walk_body_height_world_units": [f["fixed_27_over_56_scale_landmarks"]["body_height_px"] / 3 for f in frames],
            "idle_body_height_world_units": [m["body_height_px"] / 3 for m in idle_measures],
            "walk_vest_height_px": [f["fixed_27_over_56_scale_landmarks"]["central_vest_orange_height_px"] for f in frames],
            "idle_vest_height_px": [m["central_vest_orange_height_px"] for m in idle_measures],
            "comparison": "Matched broad heads remain 94-95px. Walk body alpha height is about 176-180px (58.7-60.0wu) versus idle 191-192px (63.7-64.0wu); the torso orange-vest proxy is 42-45px versus idle 49px. This is a real body/vest source-proportion gap under the shared scale; some extra height difference is natural gait crouch, but vest shortening is not explained by the lower legs alone and remains open.",
        },
        "support_foot_anchors": manual_anchors,
        "anchor_method": "Manual sole-contact x is the horizontal midpoint of the alpha>=16 outsole run on the lowest visible row in the support-boot ROI; row may be y228 where antialias/rounding leaves one transparent row above registered y229 baseline. Coordinates are cell pixel centers; world x = pixel x/3 at fixed 64/192 scale. Raw source bounds are inverse-mapped from the registered ROI using the frozen 27/56 scale and per-frame rigid paste offset.",
        "anchor_travel_analysis": {
            "near_support_K1_to_K4_cell_px": [manual_anchors[i]["contact_x_px"] for i in range(4)],
            "near_support_K1_to_K4_world_px": [manual_anchors[i]["contact_x_px"] / 3 for i in range(4)],
            "near_support_contact_delta_world_px_per_pose": [round((manual_anchors[i + 1]["contact_x_px"] - manual_anchors[i]["contact_x_px"]) / 3, 2) for i in range(3)],
            "far_support_K5_to_K8_cell_px": [manual_anchors[i]["contact_x_px"] for i in range(4, 8)],
            "far_support_K5_to_K8_world_px": [manual_anchors[i]["contact_x_px"] / 3 for i in range(4, 8)],
            "far_support_contact_delta_world_px_per_pose": [round((manual_anchors[i + 1]["contact_x_px"] - manual_anchors[i]["contact_x_px"]) / 3, 2) for i in range(4, 7)],
            "current_game_translation_reference_world_px_per_pose": 13,
            "interpretation": "Near support advances right about 3.0 world px per pose across K1-K4, short of +13 needed to hold a world-space foot point while the character moves west 13px/pose; expected residual slide is roughly 10px/pose. Far support x marks are less regular and include a low-confidence K5/K7 segment, so no clean cycle-wide estimate is claimed. This is an art-side contact diagnostic, not a stride/timing change.",
        },
        "review_artifacts": {
            "support_foot_roi_sheet": {"path": str(contact_path.relative_to(ROOT)), "sha256": sha(contact_path), "description": "Whole 256px cells with 16px grid and enlarged support-foot ROIs for manual contact marking; labels specify planned support leg and ROI."},
            "support_sole_coordinate_detail": {"path": str(foot_detail_path.relative_to(ROOT)), "sha256": sha(foot_detail_path), "description": "Support-leg sole crop at 4x nearest-neighbor with x labels every 8 cell pixels and red y=229 ground line; used to record manual x centers."},
            "weak_alpha_source_trace": {"path": str(trace_path.relative_to(ROOT)), "sha256": sha(trace_path), "description": "Raw atlas crops with the 398 alpha 1..15 pixels outside render crops recolored magenta for source-context tracing."},
        },
        "open_findings": ["V4 is still a proposal; root acceptance/integration required.", "Vest/body proportions remain shorter than approved idle at the shared head scale.", "K5 support contact is low confidence and K7 has leg overlap; far-foot cycle anchor is therefore provisional.", "The art-side support contacts move too little to cancel the current 13-world-px-per-pose westward translation; runtime stride remains root-owned."],
    }
    audit_path = OUT_SOURCE / "v4-contact-and-proportion-audit.json"
    audit_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"audit": str(audit_path), "contact_sheet": str(contact_path), "omitted_weak_alpha": all_omitted, "per_phase_components": [f["omitted_weak_alpha_component_count"] for f in frames]}, indent=2))


if __name__ == "__main__":
    main()
