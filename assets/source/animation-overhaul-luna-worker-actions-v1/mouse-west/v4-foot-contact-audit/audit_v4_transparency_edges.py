"""Review frozen West V4 sprites over contrasting opaque backgrounds.

No source asset is modified. The contact sheet is diagnostic only and makes
alpha-edge halos easier to distinguish from the artwork's pink tail/ear.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
STRIP = ROOT / "assets/source/animation-overhaul-luna-worker-actions-v1/mouse-west/canonical-8phase-v4-empty-gap-registration/field-mouse-technician-west-canonical-8phase-v4-gap-registered-8x1.png"
OLD_AUDIT = HERE / "v4-contact-and-proportion-audit.json"
OUTDIR = ROOT / "output/animation-overhaul/luna-worker-actions/mouse-west/v4-foot-contact-audit"
OUTDIR.mkdir(parents=True, exist_ok=True)

BG_COLORS = [
    (18, 20, 24),       # dark neutral
    (245, 245, 245),    # white
    (0, 230, 190),      # saturated green-cyan
    (180, 35, 210),     # magenta
]
BG_NAMES = ["dark", "white", "cyan", "magenta"]
CELL = 256
ZOOM = 2


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    strip = Image.open(STRIP).convert("RGBA")
    if strip.size != (2048, 256):
        raise ValueError(f"Unexpected frozen strip size {strip.size}")
    font = ImageFont.load_default()
    panel_size = CELL * ZOOM
    header = 22
    sheet = Image.new("RGB", (panel_size * 4, (panel_size + header) * 2), (33, 37, 43))
    phase_metrics = []

    for i in range(8):
        sprite = strip.crop((i * CELL, 0, (i + 1) * CELL, CELL))
        rgba = np.asarray(sprite)
        alpha = rgba[:, :, 3]
        counts = {
            "alpha_zero": int(np.count_nonzero(alpha == 0)),
            "alpha_1_15": int(np.count_nonzero((alpha > 0) & (alpha < 16))),
            "alpha_16_254": int(np.count_nonzero((alpha >= 16) & (alpha < 255))),
            "alpha_255": int(np.count_nonzero(alpha == 255)),
            "alpha_ge16_canvas_edges": {
                "top": int(np.count_nonzero(alpha[0, :] >= 16)),
                "bottom": int(np.count_nonzero(alpha[-1, :] >= 16)),
                "left": int(np.count_nonzero(alpha[:, 0] >= 16)),
                "right": int(np.count_nonzero(alpha[:, -1] >= 16)),
            },
        }
        phase_metrics.append({"phase": i + 1, **counts})

        panel = Image.new("RGB", (CELL * 2, CELL * 2), (33, 37, 43))
        positions = [(0, 0), (CELL, 0), (0, CELL), (CELL, CELL)]
        for bg, position in zip(BG_COLORS, positions):
            background = Image.new("RGBA", (CELL, CELL), (*bg, 255))
            background.alpha_composite(sprite)
            panel.paste(background.convert("RGB"), position)
        panel = panel.resize((panel_size, panel_size), Image.Resampling.NEAREST)
        draw = ImageDraw.Draw(sheet)
        x = (i % 4) * panel_size
        y = (i // 4) * (panel_size + header)
        draw.text((x + 5, y + 4), f"K{i+1} — dark / white / cyan / magenta edge review", fill=(255, 245, 150), font=font)
        sheet.paste(panel, (x, y + header))

    sheet_path = OUTDIR / "field-mouse-west-v4-contrast-alpha-edge-review.png"
    sheet.save(sheet_path, optimize=True)

    prior = json.loads(OLD_AUDIT.read_text(encoding="utf-8"))
    anchors = prior["support_foot_anchors"]
    path_rows = []
    for anchor in anchors:
        path_rows.append({
            "phase": anchor["phase"],
            "support_leg": anchor["support_leg"],
            "contact_x_cell_px": anchor["contact_x_px"],
            "contact_y_cell_px": anchor["contact_y_px"],
            "world_x_at_64_over_192": round(anchor["contact_x_px"] / 3, 3),
            "confidence": anchor["confidence"],
            "sole_roi_cell_px": anchor["roi_xyxy"],
            "raw_source_alpha_ge16_bbox_global": anchor["raw_source_alpha_ge16_bbox_global_xyxy"],
        })

    output = {
        "status": "review-only; frozen V4 source unchanged; no runtime promotion",
        "source_strip": {"path": str(STRIP), "sha256": sha(STRIP), "dimensions": list(strip.size), "mode": "RGBA"},
        "prior_foot_audit": {"path": str(OLD_AUDIT), "sha256": sha(OLD_AUDIT)},
        "phase_order": [
            "K1 near/pocketed contact",
            "K2 near support/load",
            "K3 far passing, near support",
            "K4 far knee-up, near support",
            "K5 far/plain contact",
            "K6 far support/load",
            "K7 near passing, far support",
            "K8 near knee-up, far support",
        ],
        "support_anchors": path_rows,
        "foot_path_summary": prior["anchor_travel_analysis"],
        "body_and_vest_summary": prior["fixed_scale_geometry"],
        "omitted_source_alpha": {
            "count": prior["weak_alpha"]["outside_final_registered_render_bounds_count"],
            "histogram": prior["weak_alpha"]["source_alpha_histogram"],
            "classification": prior["weak_alpha"]["component_location_summary"],
            "fixed_64px_render_impact": prior["weak_alpha"]["visual_impact_at_fixed_64_world_scale"],
        },
        "alpha_by_phase": phase_metrics,
        "edge_review": {
            "rendered_over": dict(zip(BG_NAMES, BG_COLORS)),
            "contact_sheet": str(sheet_path),
            "contact_sheet_sha256": sha(sheet_path),
            "visual_result": "True RGBA transparency is preserved. No checkerboard is encoded in the candidate strip and no detached red or checker fringe is apparent at native review scale over dark, white, cyan and magenta fields. Artwork's orange-pink tail and near ear remain expected opaque-color regions. Source alpha=1 flecks outside registered crops remain separately documented in the prior audit; they are not visible in the registered strip.",
            "all_phases_have_zero_alpha_ge16_on_canvas_edges": all(
                all(v == 0 for v in frame["alpha_ge16_canvas_edges"].values()) for frame in phase_metrics
            ),
        },
        "open_gates": [
            "Stride registration: near support advances +3 world px per pose against +13 required; approximate residual slide is 10px per pose.",
            "Far support anchors are irregular and K5/K7 are lower confidence due short outsole extent and leg overlap.",
            "Walk body is about 176–180 cell px versus 191–192 for idle at matching 94–95px head scale; orange vest is 42–45px versus 48px for idle. The head matches while torso/vest remains shorter.",
            "K6 remains a soft weight-down/heel-lift reference, not a strong load-settle pose.",
            "No deterministic rigid translation fixes the foot path without moving the fixed torso axis; changing lower-leg pose requires a new art master and is outside this source-only review.",
        ],
    }
    out_json = OUTDIR / "v4-transparency-edge-and-gait-audit.json"
    out_json.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"strip_sha256={sha(STRIP)}")
    print(f"sheet={sheet_path}\nsheet_sha256={sha(sheet_path)}")
    print(f"json={out_json}\njson_sha256={sha(out_json)}")
    print("all_canvas_edges_alpha_ge16_zero=", output["edge_review"]["all_phases_have_zero_alpha_ge16_on_canvas_edges"])
    for item in path_rows:
        print(f"K{item['phase']} {item['support_leg']} x={item['contact_x_cell_px']} cell ({item['world_x_at_64_over_192']} world) conf={item['confidence']}")


if __name__ == "__main__":
    main()
