from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = ROOT / "character-motion" / "rabbit-worker.json"


def project_path(value: str, root: Path) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def visible_bottom(frame: Image.Image, roi: list[int], scale: float, alpha_threshold: int) -> int | None:
    x0, y0, x1, y1 = (round(value * scale) for value in roi)
    alpha = frame.convert("RGBA").getchannel("A")
    x0, x1 = max(0, x0), min(frame.width, x1)
    y0, y1 = max(0, y0), min(frame.height, y1)
    if x0 >= x1 or y0 >= y1:
        return None
    mask = alpha.crop((x0, y0, x1, y1)).point(lambda value: 255 if value > alpha_threshold else 0)
    bbox = mask.getbbox()
    return None if bbox is None else y0 + bbox[3]


def audit(spec_path: Path, project_root: Path, sheet_override: Path | None,
          output_path: Path | None, frame_width_override: int | None,
          frame_height_override: int | None, frame_count_override: int | None,
          columns_override: int | None, pose_subdivisions: int,
          alpha_threshold: int) -> dict:
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    contract = spec["foot_contact_contract"]
    animation = spec["animations"][contract["walk_animation"]]
    sheet_path = (project_path(str(sheet_override), project_root) if sheet_override
                  else project_path(animation["path"], project_root))
    with Image.open(sheet_path) as opened:
        sheet = opened.convert("RGBA")

    frame_width = frame_width_override or int(animation["frame_width"])
    frame_height = frame_height_override or int(animation["frame_height"])
    frame_count = frame_count_override or int(animation["frame_count"])
    columns = columns_override or frame_count
    rows = (frame_count + columns - 1) // columns
    if sheet.width != frame_width * columns or sheet.height != frame_height * rows:
        raise SystemExit(
            f"{sheet_path} is {sheet.width}x{sheet.height}; expected a {columns}-column "
            f"atlas of {frame_count} {frame_width}x{frame_height} cells"
        )

    # ROIs and the target are expressed in the V7 512px reference-cell scale.
    scale = frame_width / float(contract["reference_frame_width_px"])
    target = float(contract["target_support_sole_delta_y_source_px_per_pose"]) * scale
    tolerance = float(contract["maximum_track_error_source_px"]) * scale
    result = {
        "title": "North-walk planted-foot track review",
        "decision": "pending",
        "sheet": str(sheet_path),
        "frame_size": [frame_width, frame_height],
        "frame_count": frame_count,
        "columns": columns,
        "rows": rows,
        "pose_subdivisions": pose_subdivisions,
        "source_scale_relative_to_v7": scale,
        "target_sole_delta_y_per_pose_px": round(target, 3),
        "max_track_error_px": round(tolerance, 3),
        "measurement": contract["measurement"],
        "tracks": [],
        "failures": [],
        "limitations": [
            "ROIs are manually reviewed, direction-specific support-boot windows.",
            "The pixel measurement is a screening gate; a passing result still requires visual review of the complete loop and game-scale motion.",
            "This audit covers stance sole travel, not toe-off shape, foot pitch, or body proportions.",
        ],
    }

    for track in contract["north_support_tracks"]:
        points = []
        for entry in track["points"]:
            phase = int(entry["phase"])
            frame_number = (phase - 1) * pose_subdivisions + 1
            if frame_number > frame_count:
                raise SystemExit(f"Support phase {phase} maps beyond frame count {frame_count}")
            zero_based = frame_number - 1
            column, row = zero_based % columns, zero_based // columns
            left, top = column * frame_width, row * frame_height
            frame = sheet.crop((left, top, left + frame_width, top + frame_height))
            bottom = visible_bottom(frame, entry["roi"], scale, alpha_threshold)
            point = {"phase": phase, "frame": frame_number,
                     "roi_reference_px": entry["roi"],
                     "sole_bottom_px": bottom}
            points.append(point)
        track_result = {"foot": track["foot"], "toe_off_by_phase": track["toe_off_by_phase"],
                        "points": points, "transitions": []}
        for first, second in zip(points, points[1:]):
            delta = None if first["sole_bottom_px"] is None or second["sole_bottom_px"] is None else second["sole_bottom_px"] - first["sole_bottom_px"]
            error = None if delta is None else delta - target
            passed = error is not None and abs(error) <= tolerance
            transition = {
                "from_phase": first["phase"], "to_phase": second["phase"],
                "measured_sole_delta_y_px": delta,
                "target_sole_delta_y_px": round(target, 3),
                "error_px": None if error is None else round(error, 3),
                "pass": passed,
            }
            track_result["transitions"].append(transition)
            if not passed:
                result["failures"].append({"foot": track["foot"], **transition})
        result["tracks"].append(track_result)

    result["decision"] = "pass" if not result["failures"] else "fail"
    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Measure North-walk support-sole travel against root movement.")
    parser.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    parser.add_argument("--project-root", type=Path, default=ROOT)
    parser.add_argument("--sheet", type=Path, help="Optional 8-frame horizontal strip to audit")
    parser.add_argument("--frame-width", type=int, help="Cell width for a staged candidate")
    parser.add_argument("--frame-height", type=int, help="Cell height for a staged candidate")
    parser.add_argument("--frame-count", type=int, help="Cell count for a staged candidate")
    parser.add_argument("--columns", type=int, help="Atlas columns for a staged candidate")
    parser.add_argument("--pose-subdivisions", type=int, default=1,
                        help="Frames per canonical gait pose in a subdivided cycle")
    parser.add_argument("--output", type=Path, help="Write a JSON result")
    parser.add_argument("--alpha-threshold", type=int, default=16)
    args = parser.parse_args()
    if args.pose_subdivisions < 1:
        parser.error("--pose-subdivisions must be at least one")
    report = audit(args.spec, args.project_root, args.sheet, args.output,
                   args.frame_width, args.frame_height, args.frame_count,
                   args.columns, args.pose_subdivisions, args.alpha_threshold)
    print(f"North support-foot track: {report['decision']} ({len(report['failures'])} transition failures)")
    for track in report["tracks"]:
        for transition in track["transitions"]:
            print(f"{track['foot']} phase {transition['from_phase']}->{transition['to_phase']}: "
                  f"{transition['measured_sole_delta_y_px']}px / "
                  f"{transition['target_sole_delta_y_px']}px target "
                  f"({'PASS' if transition['pass'] else 'FAIL'})")
    if args.output:
        print(f"Report: {args.output}")


if __name__ == "__main__":
    main()
