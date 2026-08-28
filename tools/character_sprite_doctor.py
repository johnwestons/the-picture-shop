"""Audit Picture Shop character strips for geometry and animation coherence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter, deque
from dataclasses import asdict, dataclass, field
from pathlib import Path
from statistics import median
from typing import Iterable, Sequence

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
CHARACTER_ROOT = ROOT / "assets" / "generated" / "characters"
OUTPUT_ROOT = ROOT / "output" / "sprite-doctor" / "audit"
ALPHA_THRESHOLD = 16


@dataclass(frozen=True)
class Component:
    area: int
    bbox: tuple[int, int, int, int]


@dataclass
class FrameMetrics:
    frame: int
    bbox: tuple[int, int, int, int] | None
    raw_bbox: tuple[int, int, int, int] | None
    components: list[Component]
    visible_pixels: int


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    frame: int | None = None
    details: dict[str, object] = field(default_factory=dict)

    def to_dict(self) -> dict[str, object]:
        return {key: value for key, value in asdict(self).items() if value not in (None, {}, [])}


@dataclass
class StripAudit:
    path: Path
    frame_size: int
    frames: list[Image.Image]
    metrics: list[FrameMetrics]
    issues: list[Issue]

    @property
    def counts(self) -> Counter[str]:
        return Counter(issue.severity for issue in self.issues)

    def to_dict(self) -> dict[str, object]:
        return {
            "path": str(self.path),
            "frame_size": self.frame_size,
            "frame_count": len(self.frames),
            "summary": dict(self.counts),
            "issues": [issue.to_dict() for issue in self.issues],
        }


def mask_bbox(mask: np.ndarray) -> tuple[int, int, int, int] | None:
    points = np.argwhere(mask)
    if not len(points):
        return None
    top, left = points.min(axis=0)
    bottom, right = points.max(axis=0)
    return int(left), int(top), int(right) + 1, int(bottom) + 1


def component_summary(mask: np.ndarray) -> list[Component]:
    """Return every 8-connected component, largest first, for every frame."""
    height, width = mask.shape
    visited = np.zeros((height, width), dtype=bool)
    result: list[Component] = []
    for start_y, start_x in np.argwhere(mask):
        y0, x0 = int(start_y), int(start_x)
        if visited[y0, x0]:
            continue
        visited[y0, x0] = True
        queue: deque[tuple[int, int]] = deque(((y0, x0),))
        area = 0
        left = right = x0
        top = bottom = y0
        while queue:
            y, x = queue.popleft()
            area += 1
            left, right = min(left, x), max(right, x)
            top, bottom = min(top, y), max(bottom, y)
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        queue.append((next_y, next_x))
        result.append(Component(area, (left, top, right + 1, bottom + 1)))
    return sorted(result, key=lambda component: component.area, reverse=True)


def color_descriptor(image: Image.Image) -> np.ndarray:
    pixels = np.asarray(image.convert("RGBA")).reshape(-1, 4)
    rgb = pixels[pixels[:, 3] > 24, :3]
    if len(rgb) == 0:
        return np.zeros(144, dtype=np.float64)
    hsv = np.asarray(
        Image.fromarray(rgb.reshape(1, -1, 3).astype(np.uint8), "RGB").convert("HSV")
    ).reshape(-1, 3).astype(np.int16)
    bucket = (
        (np.minimum(11, hsv[:, 0] * 12 // 256) * 4 + np.minimum(3, hsv[:, 1] * 4 // 256)) * 3
        + np.minimum(2, hsv[:, 2] * 3 // 256)
    )
    histogram = np.bincount(bucket, minlength=144).astype(np.float64)
    return histogram / histogram.sum() if histogram.sum() else histogram


def combined_descriptor(frames: Iterable[Image.Image]) -> np.ndarray:
    result = np.sum([color_descriptor(frame) for frame in frames], axis=0)
    return result / result.sum() if result.sum() else result


def descriptor_distance(left: np.ndarray, right: np.ndarray) -> float:
    return float(np.sqrt(np.square(np.sqrt(left) - np.sqrt(right)).sum()) / math.sqrt(2))


def aligned_mask(frame: Image.Image, metric: FrameMetrics, size: int) -> np.ndarray:
    source = np.asarray(frame.convert("RGBA").getchannel("A")) > ALPHA_THRESHOLD
    canvas = np.zeros((size, size), dtype=bool)
    if not metric.bbox:
        return canvas
    left, _, right, bottom = metric.bbox
    shift_x = round(size / 2 - (left + right) / 2)
    shift_y = round(size * 0.9 - bottom)
    source_y0, source_x0 = max(0, -shift_y), max(0, -shift_x)
    target_y0, target_x0 = max(0, shift_y), max(0, shift_x)
    height = min(size - source_y0, size - target_y0)
    width = min(size - source_x0, size - target_x0)
    if height > 0 and width > 0:
        canvas[target_y0:target_y0 + height, target_x0:target_x0 + width] = (
            source[source_y0:source_y0 + height, source_x0:source_x0 + width]
        )
    return canvas


def silhouette_distance(left: np.ndarray, right: np.ndarray) -> float:
    union = int(np.logical_or(left, right).sum())
    return 0.0 if not union else 1.0 - int(np.logical_and(left, right).sum()) / union


def audit_strip(image_or_path: Image.Image | Path, label: Path | None = None) -> StripAudit:
    if isinstance(image_or_path, Path):
        path = image_or_path
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
    else:
        path = label or Path("<prepared-strip>")
        image = image_or_path.convert("RGBA")
    issues: list[Issue] = []
    if image.height <= 0 or image.width % image.height:
        issues.append(Issue("error", "sheet_dimensions", "sheet must contain square horizontal frames"))
        return StripAudit(path, image.height, [], [], issues)
    size = image.height
    frames = [image.crop((x, 0, x + size, size)) for x in range(0, image.width, size)]
    metrics: list[FrameMetrics] = []
    for index, frame in enumerate(frames, 1):
        alpha = np.asarray(frame.getchannel("A"))
        significant = alpha > ALPHA_THRESHOLD
        components = component_summary(significant)
        metric = FrameMetrics(index, mask_bbox(significant), mask_bbox(alpha > 0), components, int(significant.sum()))
        metrics.append(metric)
        if not metric.bbox:
            issues.append(Issue("error", "empty_frame", "frame has no significant sprite pixels", index))
            continue
        left, top, right, bottom = metric.bbox
        if left <= 2 or top <= 2 or right >= size - 2 or bottom >= size - 2:
            issues.append(Issue(
                "error", "clipped_frame", "significant art touches a frame edge and may be cropped",
                index, {"bbox": metric.bbox},
            ))
        if metric.raw_bbox:
            halo = max(abs(raw - significant_value) for raw, significant_value in zip(metric.raw_bbox, metric.bbox))
            if halo > 8:
                issues.append(Issue(
                    "warning", "alpha_halo",
                    f"raw alpha extends {halo}px beyond the significant sprite", index,
                    {"raw_bbox": metric.raw_bbox, "significant_bbox": metric.bbox},
                ))
        if len(components) > 1:
            detached = components[1:]
            issues.append(Issue(
                "warning", "disconnected_components",
                f"frame has {len(detached)} component(s) detached from the main subject", index,
                {"detached": [asdict(component) for component in detached]},
            ))
            total = sum(component.area for component in components)
            boundary = [
                component for component in detached
                if component.area >= max(16, round(total * 0.003))
                and (component.bbox[0] <= 1 or component.bbox[2] >= size - 1)
            ]
            if boundary:
                issues.append(Issue(
                    "warning", "panel_boundary_fragment",
                    "a substantial detached component enters from a horizontal panel boundary", index,
                    {"components": [asdict(component) for component in boundary]},
                ))

    usable = [metric for metric in metrics if metric.bbox]
    if len(usable) > 1:
        tops = [metric.bbox[1] for metric in usable if metric.bbox]
        heights = [metric.bbox[3] - metric.bbox[1] for metric in usable if metric.bbox]
        top_limit = max(12, round(float(median(heights)) * 0.08))
        if max(tops) - min(tops) > top_limit:
            issues.append(Issue(
                "warning", "top_bound_jitter",
                f"frame top bounds vary by {max(tops) - min(tops)}px; expected at most {top_limit}px",
                details={"tops": tops, "limit": top_limit},
            ))
        bottoms = [metric.bbox[3] for metric in usable if metric.bbox]
        if max(bottoms) - min(bottoms) > max(4, round(size * 0.015)):
            issues.append(Issue(
                "warning", "baseline_jitter",
                f"frame bottoms vary by {max(bottoms) - min(bottoms)}px",
                details={"bottoms": bottoms},
            ))
        centers = [(metric.bbox[0] + metric.bbox[2]) / 2 for metric in usable if metric.bbox]
        if max(centers) - min(centers) > max(6, round(size * 0.02)):
            issues.append(Issue(
                "warning", "center_jitter",
                f"frame centers vary by {max(centers) - min(centers):g}px",
                details={"centers": centers},
            ))
        descriptors = [color_descriptor(frame) for frame in frames]
        shared = combined_descriptor(frames)
        masks = [aligned_mask(frame, metric, size) for frame, metric in zip(frames, metrics)]
        scale: list[dict[str, object]] = []
        palette: list[dict[str, object]] = []
        silhouette: list[dict[str, object]] = []
        for index in range(len(metrics) - 1):
            left, right = metrics[index], metrics[index + 1]
            if not left.bbox or not right.bbox:
                continue
            lw, lh = left.bbox[2] - left.bbox[0], left.bbox[3] - left.bbox[1]
            rw, rh = right.bbox[2] - right.bbox[0], right.bbox[3] - right.bbox[1]
            width_change = abs(rw - lw) / max(1, min(lw, rw))
            height_change = abs(rh - lh) / max(1, min(lh, rh))
            # A walk cycle naturally becomes wider at heel strike than at its
            # passing poses. Height drift still indicates scale instability;
            # width alone becomes suspicious only beyond a normal full stride.
            width_limit = 0.30 if path.stem == "walk" or path.stem.startswith("walk_") else 0.10
            if height_change > 0.10 or width_change > width_limit:
                scale.append({"frames": [index + 1, index + 2], "width": round(width_change, 4), "height": round(height_change, 4)})
            palette_change = descriptor_distance(descriptors[index], descriptors[index + 1])
            if palette_change > 0.30:
                palette.append({"frames": [index + 1, index + 2], "distance": round(palette_change, 4)})
            shape_change = silhouette_distance(masks[index], masks[index + 1])
            if shape_change > 0.68:
                silhouette.append({"frames": [index + 1, index + 2], "distance": round(shape_change, 4)})
        identity = [
            {"frame": index + 1, "distance": round(descriptor_distance(value, shared), 4)}
            for index, value in enumerate(descriptors) if descriptor_distance(value, shared) > 0.30
        ]
        digest_frames: dict[str, list[int]] = {}
        for index, frame in enumerate(frames, 1):
            digest = hashlib.sha256(frame.convert("RGBA").tobytes()).hexdigest()
            digest_frames.setdefault(digest, []).append(index)
        duplicate_groups = [group for group in digest_frames.values() if len(group) > 1]
        if duplicate_groups:
            issues.append(Issue(
                "warning", "exact_duplicate_frames", "one or more animation frames are byte-identical",
                details={"groups": duplicate_groups},
            ))
        if len(frames) > 1 and len(digest_frames) <= max(1, len(frames) // 2):
            issues.append(Issue(
                "warning", "low_effective_motion",
                f"{len(frames)} frames contain only {len(digest_frames)} unique image(s)",
                details={"frames": len(frames), "unique_images": len(digest_frames)},
            ))
        if (path.stem == "idle" or path.stem == "walk"
            or path.stem.startswith("idle_") or path.stem.startswith("walk_")) \
            and len(masks) > 1:
            internal_distances = [
                silhouette_distance(masks[index], masks[index + 1])
                for index in range(len(masks) - 1)
            ]
            seam = silhouette_distance(masks[-1], masks[0])
            internal = float(median(internal_distances)) if internal_distances else 0.0
            if seam > max(0.55, internal * 1.8 + 0.05):
                issues.append(Issue(
                    "warning", "loop_seam",
                    f"loop seam distance {seam:.3f} exceeds internal median {internal:.3f}",
                    details={"seam_distance": round(seam, 4), "internal_median": round(internal, 4)},
                ))
        for code, message, comparisons in (
            ("adjacent_scale_jump", "adjacent frames have an abrupt visible-size change", scale),
            ("adjacent_palette_jump", "adjacent frames have an abrupt palette change", palette),
            ("adjacent_silhouette_jump", "adjacent frames have an abrupt silhouette change", silhouette),
            ("frame_identity_drift", "one or more frames drift from the action's shared visual identity", identity),
        ):
            if comparisons:
                issues.append(Issue("warning", code, message, details={"comparisons": comparisons}))
    return StripAudit(path, size, frames, metrics, issues)


def render_contact_sheet(audit: StripAudit, destination: Path) -> None:
    cell = 192
    sheet = Image.new("RGBA", (cell * max(1, len(audit.frames)), cell + 28), (32, 36, 42, 255))
    draw = ImageDraw.Draw(sheet)
    for index, frame in enumerate(audit.frames):
        preview = frame.resize((cell, cell), Image.Resampling.NEAREST)
        sheet.alpha_composite(preview, (index * cell, 28))
        draw.text((index * cell + 8, 7), f"frame {index + 1}", fill=(245, 225, 170, 255))
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def discover_strips(root: Path) -> list[Path]:
    return sorted(path for path in root.glob("*/*.png") if path.is_file())


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--contact-sheets", type=Path, default=OUTPUT_ROOT / "contact-sheets")
    parser.add_argument("--report", type=Path, default=OUTPUT_ROOT / "report.json")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args(argv)
    paths = args.paths or discover_strips(CHARACTER_ROOT)
    audits = [audit_strip(path.resolve()) for path in paths]
    for audit in audits:
        render_contact_sheet(audit, args.contact_sheets / audit.path.parent.name / audit.path.name)
    report = {"strips": [audit.to_dict() for audit in audits]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    errors = sum(audit.counts["error"] for audit in audits)
    warnings = sum(audit.counts["warning"] for audit in audits)
    print(f"Audited {len(audits)} strip(s): {errors} error(s), {warnings} warning(s)")
    print(f"Contact sheets: {args.contact_sheets.resolve()}")
    print(f"Report: {args.report.resolve()}")
    return 1 if errors or (args.strict and warnings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
