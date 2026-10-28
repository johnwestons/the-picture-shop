"""Audit the one authorized lower-body stride correction attempt.

This is review-only: it does not remove the baked checkerboard, reconstruct
transparency, or create a runtime sprite. Manual sole and torso-axis marks are
reported with their uncertainty because the generated image has no alpha.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
RAW = HERE / "field-mouse-west-stride-contact-correction-v1-raw.png"
V4_STRIP = ROOT / "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/canonical-8phase-v4-empty-gap-registration/field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png"
TARGET_GUIDE = HERE / "field-mouse-west-v4-contact-target-guide-4x2.png"
IDLE = ROOT / "assets/generated/technician-motion-v2/field-mouse-technician/idle_west.png"
OUTDIR = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/stride-contact-correction-v1"
OUTDIR.mkdir(parents=True, exist_ok=True)

# The correction prompt requested 512-square cells, but ImageGen returned
# 1774x887. This is the exact uniform source-pixel scale for an evenly divided
# 4x2 atlas. The operator axis and sole centers below were selected manually
# against the original grid-marked review and carry ~4 normalized-pixel error.
TARGET_X = [104, 143, 182, 221, 104, 143, 182, 221]
TARGET_Y = 229
TORSO_AXIS_RAW_X = [220, 219, 220, 218, 220, 218, 218, 218]
SOLE_RAW = [
    (130, 431, "near/pocketed lead contact", "medium"),
    (159, 430, "near/pocketed planted support", "medium"),
    (200, 432, "near/pocketed planted support", "low; boot overlap"),
    (218, 432, "near/pocketed planted support", "medium"),
    (125, 415, "far/plain lead contact", "medium"),
    (160, 415, "far/plain planted support", "medium"),
    (220, 414, "far/plain planted support", "low; leg overlap"),
    (225, 416, "far/plain planted support", "low; leg overlap"),
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    image = Image.open(RAW)
    raw_mode = image.mode
    rgb = image.convert("RGB")
    w, h = rgb.size
    x_edges = [round(i * w / 4) for i in range(5)]
    y_edges = [round(i * h / 2) for i in range(3)]
    scale_x = (w / 4) / 256
    scale_y = (h / 2) / 256

    font = ImageFont.load_default()
    pad = 28
    tile_w, tile_h = 540, 540
    sheet = Image.new("RGB", (tile_w * 4, tile_h * 2), (27, 31, 36))
    frames = []

    for i in range(8):
        col, row = i % 4, i // 4
        x0, x1 = x_edges[col], x_edges[col + 1]
        y0, y1 = y_edges[row], y_edges[row + 1]
        cell = rgb.crop((x0, y0, x1, y1))
        cw, ch = cell.size
        sx, sy = cw / 256, ch / 256
        axis = TORSO_AXIS_RAW_X[i]
        sole_x, sole_y, phase, confidence = SOLE_RAW[i]
        target_x = axis + (TARGET_X[i] - 128) * sx
        target_y = TARGET_Y * sy
        registered_x = 128 + (sole_x - axis) / sx
        delta = registered_x - TARGET_X[i]
        # Ground is rigidly normalized to y=229 for comparing the horizontal
        # contact track. Keep source y as evidence; no per-frame rescaling.
        art = cell.resize((500, 500), Image.Resampling.LANCZOS)
        # Display the whole source cell after only rigid translation: axis to
        # x=128 and selected support sole to y=229. This makes the target and
        # observed sole directly comparable without hiding the baked checker.
        dx = round((128 - axis / sx) * 500 / 256)
        dy = round((TARGET_Y - sole_y / sy) * 500 / 256)
        shown = Image.new("RGB", (500, 500), (27, 31, 36))
        shown.paste(art, (dx, dy))
        d = ImageDraw.Draw(shown)
        fx = 500 / 256
        ax, tx = 128 * fx, TARGET_X[i] * fx
        ty = TARGET_Y * fx
        actual_x = registered_x * fx
        d.line((ax, 0, ax, 500), fill=(50, 130, 255), width=2)
        d.line((0, ty, 500, ty), fill=(250, 75, 75), width=2)
        d.ellipse((tx - 8, ty - 8, tx + 8, ty + 8), outline=(30, 255, 245), width=3)
        d.line((actual_x - 7, ty, actual_x + 7, ty), fill=(255, 235, 50), width=3)
        d.line((actual_x, ty - 7, actual_x, ty + 7), fill=(255, 235, 50), width=3)
        d.rectangle((0, 0, 300, 37), fill=(20, 23, 27))
        d.text((5, 4), f"K{i+1}: {phase}", fill=(255, 245, 120), font=font)
        d.text((5, 19), f"sole {registered_x:.1f} vs target {TARGET_X[i]} ({delta:+.1f}); {confidence}", fill=(255, 255, 255), font=font)
        sheet.paste(shown, (col * tile_w + 20, row * tile_h + 20))

        frames.append({
            "phase": i + 1,
            "support_role": phase,
            "target_registered_cell_px": [TARGET_X[i], TARGET_Y],
            "measured_sole_source_cell_px_manual": [sole_x, sole_y],
            "manual_torso_axis_source_cell_x": axis,
            "fixed_uniform_source_to_cell_scale": [1 / sx, 1 / sy],
            "measured_registered_sole_cell_x": round(registered_x, 2),
            "horizontal_error_cell_px": round(delta, 2),
            "confidence": confidence,
            "estimated_measurement_uncertainty_cell_px": 4,
        })

    overlay = OUTDIR / "stride-correction-v1-target-vs-sole-review.png"
    sheet.save(overlay, optimize=True)

    json_path = OUTDIR / "stride-correction-v1-foot-path-measurements.json"
    measurements = {
        "status": "rejected-review-only",
        "reason": "ImageGen returned RGB checkerboard baked into pixels (no alpha); manual contact soles also miss the explicit support path after fixed torso-axis registration.",
        "source": {"path": str(RAW), "sha256": sha(RAW), "dimensions": [w, h], "mode": raw_mode},
        "references": {
            "v4_strip_sha256": sha(V4_STRIP),
            "target_guide_sha256": sha(TARGET_GUIDE),
            "approved_idle_sha256": sha(IDLE),
        },
        "registration": {
            "cell_layout": "4x2 evenly partitioned from returned image; actual cells are 443/444 px, not prompted 512 px",
            "whole_character_scale_raw_px_per_256_cell_px": [round(scale_x, 6), round(scale_y, 6)],
            "torso_axis_cell_x": 128,
            "ground_cell_y": 229,
            "targets_cell_px": [[x, TARGET_Y] for x in TARGET_X],
            "support_targets_advance": "39 cell px per 3 pose transitions (13 world px per phase at 64/192 scale)",
            "measurement_method": "manual pixel inspection on original RGB grid review; fixed uniform source-to-cell scale and rigid torso-axis registration; no alpha segmentation",
            "uncertainty_cell_px": 4,
        },
        "frames": frames,
        "complete_cycle": {
            "near_support_k1_to_k4_measured_cell_delta": round(frames[3]["measured_registered_sole_cell_x"] - frames[0]["measured_registered_sole_cell_x"], 2),
            "near_support_required_cell_delta": 117,
            "far_support_k5_to_k8_measured_cell_delta": round(frames[7]["measured_registered_sole_cell_x"] - frames[4]["measured_registered_sole_cell_x"], 2),
            "far_support_required_cell_delta": 117,
            "acceptance": "fails: contacts/load positions do not follow the target travel while torso axis and scale remain fixed; do not register or promote this candidate",
        },
        "review_overlay": {"path": str(overlay), "sha256": sha(overlay)},
    }
    json_path.write_text(json.dumps(measurements, indent=2), encoding="utf-8")
    print(f"raw_sha256={sha(RAW)}")
    print(f"overlay={overlay}\noverlay_sha256={sha(overlay)}")
    print(f"measurements={json_path}\nmeasurements_sha256={sha(json_path)}")
    for f in frames:
        print(f"K{f['phase']}: measured={f['measured_registered_sole_cell_x']:.1f} target={f['target_registered_cell_px'][0]} dx={f['horizontal_error_cell_px']:+.1f} conf={f['confidence']}")
    print("near delta", measurements["complete_cycle"]["near_support_k1_to_k4_measured_cell_delta"])
    print("far delta", measurements["complete_cycle"]["far_support_k5_to_k8_measured_cell_delta"])


if __name__ == "__main__":
    main()
