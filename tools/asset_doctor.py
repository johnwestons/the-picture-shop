"""Audit Picture Shop raster assets using the Mouse Frontier workflow principles."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


def result(name: str, passed: bool, detail: str) -> dict[str, object]:
    return {"name": name, "passed": passed, "detail": detail}


def audit(root: Path) -> list[dict[str, object]]:
    generated = root / "assets" / "generated"
    paths = {
        "warehouse": generated / "warehouse-layout-final.png",
        "walkmask": generated / "warehouse-layout-final-walkmask.png",
        "rabbit_idle": generated / "characters" / "rabbit-worker" / "idle.png",
        "rabbit_walk": generated / "characters" / "rabbit-worker" / "walk.png",
        "polar": generated / "polar-115-sprite-sheet-clear-table-transparent.png",
        "polar_directions": generated / "polar-cutter-directions-strip.png",
        "empty_pallet": generated / "empty-pallet.png",
        "paper_stack": generated / "paper-stack.png",
        "toolbox_small": generated / "toolbox-small.png",
        "toolbox_large": generated / "toolbox-large.png",
        "paper_boxes": generated / "paper-storage-boxes-strip.png",
        "picture_press": generated / "picture-press-transparent.png",
        "windmill_directions": generated / "heidelberg-windmill-directions-atlas-v1.png",
        "press_process_stages": generated / "press-process-stages-atlas-v3.png",
        "press_operator_handbook": generated / "heidelberg-operator-handbook-atlas-v2.png",
        "press_setup_interactions": generated / "heidelberg-setup-interactions-atlas-v2.png",
        "technician_npcs": generated / "technician-npcs-atlas-v1.png",
        "skid_wrapper_directions": generated / "skid-wrapper-directions-strip.png",
        "wrapped_pallet_stages": generated / "wrapped-pallet-stages-strip.png",
        "loading_bay_door": generated / "loading-bay-door-strip.png",
        "delivery_truck": generated / "delivery-truck-open.png",
        "truck_cargo_door": generated / "truck-cargo-door-strip.png",
        "machine_flatbed_loaded": generated / "machine-delivery-flatbed-loaded.png",
        "machine_flatbed_empty": generated / "machine-delivery-flatbed-empty.png",
        "polar_operator_console": generated / "polar-operator-console.png",
        "cutter_control_buttons": generated / "cutter-control-buttons-strip.png",
        "cutter_clamp": generated / "cutter-clamp-strip.png",
        "cutter_blade": generated / "cutter-blade-strip.png",
        "cutter_maintenance_oil": generated / "cutter-maintenance-oil-atlas.png",
        "cutter_maintenance_tools": generated / "cutter-maintenance-tools-atlas.png",
        "cutter_maintenance_scenes": generated / "cutter-maintenance-scenes-atlas.png",
        "loaded_paper_pallet": generated / "loaded-paper-pallet.png",
        "loaded_paper_pallet_directions": generated / "loaded-paper-pallet-directions-strip.png",
        "pallet_jack": generated / "pallet-jack-directions-strip.png",
        "pallet_jack_loaded": generated / "pallet-jack-loaded-directions-strip.png",
        "wall_vent_fan": generated / "wall-vent-fan-strip.png",
        "vendor_product_pallets": generated / "vendor-product-pallets-atlas.png",
        "boxed_paper_pallet_stages": generated / "boxed-paper-pallet-stages-atlas.png",
        "polar_back_button": generated / "polar-back-button-states-strip.png",
        "pallet_work_order_paper": generated / "pallet-work-order-paper-v1.png",
    }
    artwork_paths = sorted((generated / "artwork").glob("*.png"))
    for artwork_path in artwork_paths:
        paths[f"artwork_{artwork_path.stem}"] = artwork_path
    checks: list[dict[str, object]] = []
    images: dict[str, Image.Image] = {}
    work_order_font = root / "assets" / "fonts" / "SpecialElite-Regular.ttf"
    work_order_font_license = root / "assets" / "fonts" / "SpecialElite-LICENSE.txt"
    checks.append(result("work_order_font_exists", work_order_font.is_file(), str(work_order_font)))
    checks.append(result("work_order_font_license_exists",
        work_order_font_license.is_file(), str(work_order_font_license)))

    for name, path in paths.items():
        exists = path.is_file()
        checks.append(result(f"{name}_exists", exists, str(path)))
        if exists:
            images[name] = Image.open(path).convert("RGBA")

    if "warehouse" in images and "walkmask" in images:
        warehouse = images["warehouse"]
        walkmask = images["walkmask"]
        minimum, maximum = warehouse.getchannel("A").getextrema()
        checks.append(
            result(
                "warehouse_transparency",
                minimum == 0 and maximum >= 250,
                f"alpha_range=({minimum}, {maximum})",
            )
        )
        checks.append(
            result(
                "walkmask_alignment",
                warehouse.size == walkmask.size,
                f"warehouse={warehouse.size} walkmask={walkmask.size}",
            )
        )
        colors = set(walkmask.convert("L").getdata())
        checks.append(
            result(
                "walkmask_binary",
                colors.issubset({0, 255}) and colors == {0, 255},
                f"values={sorted(colors)[:16]}",
            )
        )

    for name, expected_frames in (("rabbit_idle", 2), ("rabbit_walk", 8)):
        strip = images.get(name)
        if not strip:
            continue
        expected_size = (512 * expected_frames, 512)
        checks.append(result(f"{name}_grid", strip.size == expected_size,
            f"size={strip.size} expected={expected_size}"))
        alpha = strip.getchannel("A")
        minimum, maximum = alpha.getextrema()
        checks.append(result(f"{name}_transparency", minimum == 0 and maximum >= 250,
            f"alpha_range=({minimum}, {maximum})"))
        empty_cells = [
            frame + 1 for frame in range(expected_frames)
            if alpha.crop((frame * 512, 0, (frame + 1) * 512, 512)).getbbox() is None
        ]
        checks.append(result(f"{name}_cells_nonempty", not empty_cells,
            f"empty_cells={empty_cells}"))

    polar = images.get("polar")
    if polar:
        minimum, maximum = polar.getchannel("A").getextrema()
        checks.append(
            result(
                "polar_transparency",
                minimum == 0 and maximum >= 250,
                f"alpha_range=({minimum}, {maximum})",
            )
        )

    work_order_paper = images.get("pallet_work_order_paper")
    if work_order_paper:
        alpha = work_order_paper.getchannel("A")
        minimum, maximum = alpha.getextrema()
        checks.append(result(
            "pallet_work_order_paper_contract",
            work_order_paper.size == (1536, 1024) and minimum == 0 and maximum == 255,
            f"size={work_order_paper.size} alpha_range=({minimum}, {maximum})",
        ))
        checks.append(result(
            "pallet_work_order_paper_center_opaque",
            alpha.getpixel((768, 512)) == 255,
            f"center_alpha={alpha.getpixel((768, 512))}",
        ))

    windmill = images.get("windmill_directions")
    if windmill:
        checks.append(result(
            "windmill_directions_dimensions",
            windmill.size == (1536, 1024),
            f"size={windmill.size} expected=(1536, 1024)",
        ))
        nonempty = []
        for row in range(2):
            for column in range(2):
                cell = windmill.crop((column * 768, row * 512, (column + 1) * 768, (row + 1) * 512))
                nonempty.append(cell.getbbox() is not None)
        checks.append(result(
            "windmill_directions_four_nonempty_views",
            all(nonempty),
            f"nonempty={nonempty}",
        ))

    press_stages = images.get("press_process_stages")
    if press_stages:
        alpha_range = press_stages.getchannel("A").getextrema()
        checks.append(result(
            "press_process_stages_transparency",
            alpha_range[0] == 0 and alpha_range[1] == 255,
            f"alpha_range={alpha_range}",
        ))

    technicians = images.get("technician_npcs")
    if technicians:
        checks.append(result(
            "technician_npcs_dimensions",
            technicians.size == (2048, 1024),
            f"size={technicians.size} expected=(2048, 1024)",
        ))
        alpha = technicians.getchannel("A")
        cells = []
        for row in range(2):
            for column in range(4):
                cell = alpha.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512))
                cells.append(cell.getbbox() is not None)
        minimum, maximum = alpha.getextrema()
        checks.append(result(
            "technician_npcs_transparency_and_cells",
            minimum == 0 and maximum >= 250 and all(cells),
            f"alpha_range=({minimum}, {maximum}) nonempty={cells}",
        ))

    loading_bay = images.get("loading_bay_door")
    if loading_bay:
        width, height = loading_bay.size
        alpha = loading_bay.getchannel("A")
        minimum, maximum = alpha.getextrema()
        checks.append(result(
            "loading_bay_door_strip",
            (width, height) == (1300, 260),
            f"size={loading_bay.size} expected=(1300, 260)",
        ))
        checks.append(result(
            "loading_bay_door_transparency",
            minimum == 0 and maximum >= 250,
            f"alpha_range=({minimum}, {maximum})",
        ))
        frame_width = width // 5 if width % 5 == 0 else 0
        empty_frames = []
        if frame_width:
            for frame in range(1, 5):
                if alpha.crop((frame * frame_width, 0, (frame + 1) * frame_width, height)).getbbox() is None:
                    empty_frames.append(frame + 1)
        checks.append(result(
            "loading_bay_open_frames_nonempty",
            frame_width == 260 and not empty_frames,
            f"empty_frames={empty_frames}",
        ))

    delivery_truck = images.get("delivery_truck")
    if delivery_truck:
        minimum, maximum = delivery_truck.getchannel("A").getextrema()
        checks.append(result(
            "delivery_truck_sprite",
            delivery_truck.size == (512, 512),
            f"size={delivery_truck.size} expected=(512, 512)",
        ))
        checks.append(result(
            "delivery_truck_transparency",
            minimum == 0 and maximum >= 250,
            f"alpha_range=({minimum}, {maximum})",
        ))

    for name in ("machine_flatbed_loaded", "machine_flatbed_empty"):
        flatbed = images.get(name)
        if flatbed:
            minimum, maximum = flatbed.getchannel("A").getextrema()
            checks.append(result(
                f"{name}_sprite",
                flatbed.size == (512, 512),
                f"size={flatbed.size} expected=(512, 512)",
            ))
            if name not in {"cutter_maintenance_tools", "cutter_maintenance_scenes"}:
                checks.append(result(
                    f"{name}_transparency",
                    minimum == 0 and maximum >= 250,
                    f"alpha_range=({minimum}, {maximum})",
                ))

    truck_cargo = images.get("truck_cargo_door")
    if truck_cargo:
        width, height = truck_cargo.size
        alpha = truck_cargo.getchannel("A")
        minimum, maximum = alpha.getextrema()
        checks.append(result(
            "truck_cargo_door_strip",
            (width, height) == (2560, 512),
            f"size={truck_cargo.size} expected=(2560, 512)",
        ))
        checks.append(result(
            "truck_cargo_door_transparency",
            minimum == 0 and maximum >= 250,
            f"alpha_range=({minimum}, {maximum})",
        ))
        nonempty = []
        if width == 2560 and height == 512:
            nonempty = [
                frame + 1 for frame in range(4)
                if alpha.crop((frame * 512, 0, (frame + 1) * 512, 512)).getbbox() is not None
            ]
            open_frame_empty = alpha.crop((2048, 0, 2560, 512)).getbbox() is None
        else:
            open_frame_empty = False
        checks.append(result(
            "truck_cargo_door_frame_contract",
            nonempty == [1, 2, 3, 4] and open_frame_empty,
            f"door_frames_nonempty={nonempty} open_frame_empty={open_frame_empty}",
        ))

    cutter_contracts = {
        "polar_directions": (4096, 512),
        "polar_operator_console": (768, 512),
        "cutter_control_buttons": (512, 128),
        "cutter_clamp": (3840, 512),
        "cutter_blade": (3840, 512),
        "cutter_maintenance_oil": (512, 512),
        "cutter_maintenance_tools": (768, 512),
        "cutter_maintenance_scenes": (1024, 768),
        "loaded_paper_pallet": (256, 256),
        "loaded_paper_pallet_directions": (1024, 256),
        "pallet_jack": (2048, 256),
        "pallet_jack_loaded": (2048, 256),
    }
    for name, expected_size in cutter_contracts.items():
        image = images.get(name)
        if image:
            minimum, maximum = image.getchannel("A").getextrema()
            checks.append(result(
                f"{name}_dimensions",
                image.size == expected_size,
                f"size={image.size} expected={expected_size}",
            ))
            checks.append(result(
                f"{name}_transparency",
                minimum == 0 and maximum >= 250,
                f"alpha_range=({minimum}, {maximum})",
            ))

    atlas_contracts = {
        "vendor_product_pallets": ((1252, 1252), 4, 4),
        "boxed_paper_pallet_stages": ((1400, 1120), 5, 4),
        "polar_back_button": ((384, 128), 3, 1),
        "wall_vent_fan": ((288, 96), 3, 1),
        "cutter_maintenance_oil": ((512, 512), 2, 2),
        "cutter_maintenance_tools": ((768, 512), 3, 2),
        "cutter_maintenance_scenes": ((1024, 768), 2, 2),
        "press_process_stages": ((1254, 1254), 2, 2),
        "press_operator_handbook": ((2560, 1024), 5, 2),
        "press_setup_interactions": ((1536, 1024), 3, 2),
    }
    for name, (expected_size, columns, rows) in atlas_contracts.items():
        image = images.get(name)
        if not image:
            continue
        exact = image.size == expected_size
        checks.append(result(
            f"{name}_exact_grid",
            exact,
            f"size={image.size} expected={expected_size} grid={columns}x{rows}",
        ))
        empty_cells = []
        if exact:
            alpha = image.getchannel("A")
            cell_width, cell_height = image.width // columns, image.height // rows
            for row in range(rows):
                for column in range(columns):
                    bounds = (
                        column * cell_width,
                        row * cell_height,
                        (column + 1) * cell_width,
                        (row + 1) * cell_height,
                    )
                    if alpha.crop(bounds).getbbox() is None:
                        empty_cells.append((column + 1, row + 1))
        checks.append(result(
            f"{name}_cells_nonempty",
            exact and not empty_cells,
            f"empty_cells={empty_cells}",
        ))

    setup_interactions = images.get("press_setup_interactions")
    if setup_interactions:
        minimum, maximum = setup_interactions.getchannel("A").getextrema()
        checks.append(result(
            "press_setup_interactions_true_transparency",
            minimum == 0 and maximum >= 250,
            f"alpha_range=({minimum}, {maximum})",
        ))

    for name in ("empty_pallet", "paper_stack", "toolbox_small", "toolbox_large", "paper_boxes"):
        image = images.get(name)
        if image:
            minimum, maximum = image.getchannel("A").getextrema()
            checks.append(
                result(
                    f"{name}_transparency",
                    minimum == 0 and maximum >= 250,
                    f"size={image.size} alpha_range=({minimum}, {maximum})",
                )
            )

    for name in sorted(key for key in images if key.startswith("artwork_")):
        image = images[name]
        minimum, maximum = image.getchannel("A").getextrema()
        checks.append(result(
            f"{name}_contract",
            image.size == (128, 128) and minimum == 0 and maximum >= 250 and image.getchannel("A").getbbox() is not None,
            f"size={image.size} alpha_range=({minimum}, {maximum})",
        ))

    wrapper = images.get("skid_wrapper_directions")
    if wrapper:
        checks.append(result("skid_wrapper_grid", wrapper.size == (2048, 512), f"size={wrapper.size}"))

    wrapped_stages = images.get("wrapped_pallet_stages")
    if wrapped_stages:
        alpha = wrapped_stages.getchannel("A")
        minimum, maximum = alpha.getextrema()
        checks.append(result(
            "wrapped_pallet_stages_grid",
            wrapped_stages.size == (1536, 512),
            f"size={wrapped_stages.size} expected=(1536, 512)",
        ))
        checks.append(result(
            "wrapped_pallet_stages_transparency",
            minimum == 0 and maximum >= 250,
            f"alpha_range=({minimum}, {maximum})",
        ))
        empty_frames = []
        if wrapped_stages.size == (1536, 512):
            for frame in range(3):
                if alpha.crop((frame * 512, 0, (frame + 1) * 512, 512)).getbbox() is None:
                    empty_frames.append(frame + 1)
        checks.append(result(
            "wrapped_pallet_stages_nonempty",
            not empty_frames,
            f"empty_frames={empty_frames}",
        ))
        alpha = wrapper.getchannel("A")
        checks.append(result("skid_wrapper_transparency", alpha.getextrema() == (0, 255), f"alpha_range={alpha.getextrema()}"))
        empty = [index + 1 for index in range(4) if alpha.crop((index * 512, 0, (index + 1) * 512, 512)).getbbox() is None]
        checks.append(result("skid_wrapper_frames_nonempty", not empty, f"empty_frames={empty}"))

    picture_press = images.get("picture_press")
    if picture_press:
        alpha = picture_press.getchannel("A")
        checks.append(result("picture_press_transparency", alpha.getextrema() == (0, 255), f"alpha_range={alpha.getextrema()}"))

    character_frames = {
        "rabbit-worker": {
            "idle": 2, "idle_north": 2, "idle_northeast": 2,
            "idle_southeast": 2, "idle_south": 2,
            "walk": 8, "walk_north": 8, "walk_northeast": 8,
            "walk_southeast": 8, "walk_south": 8,
        },
        "tan-cat": {"idle": 2, "walk": 3, "sit": 2},
        "green-blazer-cat": {"idle": 2, "walk": 3, "sit": 2, "use": 3},
        "blue-coaler-cat": {"idle": 2, "walk": 3, "sit": 2},
        "business-dragon": {"idle": 2, "walk": 4, "sit": 2},
        "business-fox": {"idle": 2, "walk": 4, "sit": 2},
        "business-cat": {
            "idle": 2, "idle_north": 2, "idle_northeast": 2,
            "idle_southeast": 2, "idle_south": 2,
            "walk": 8, "walk_north": 8, "walk_northeast": 8,
            "walk_southeast": 8, "walk_south": 8, "sit": 2,
        },
    }
    for character, actions in character_frames.items():
        for action, expected in actions.items():
            path = generated / "characters" / character / f"{action}.png"
            exists = path.is_file()
            checks.append(result(f"{character}_{action}_exists", exists, str(path)))
            if not exists:
                continue
            image = Image.open(path).convert("RGBA")
            width, height = image.size
            alpha = image.getchannel("A")
            minimum, maximum = alpha.getextrema()
            actual = width // 512 if height == 512 and width % 512 == 0 else 0
            checks.append(result(f"{character}_{action}_strip", actual == expected, f"size={image.size} frames={actual}"))
            checks.append(result(f"{character}_{action}_transparency", minimum == 0 and maximum >= 250, f"alpha_range=({minimum}, {maximum})"))
            empty = [frame + 1 for frame in range(actual) if alpha.crop((frame * 512, 0, (frame + 1) * 512, 512)).getbbox() is None]
            checks.append(result(f"{character}_{action}_nonempty", not empty, f"empty_frames={empty}"))
            edge_cropped = []
            for frame in range(actual):
                bounds = alpha.crop((frame * 512, 0, (frame + 1) * 512, 512)).getbbox()
                if bounds and (bounds[0] <= 0 or bounds[1] <= 0 or bounds[2] >= 512 or bounds[3] >= 512):
                    edge_cropped.append(frame + 1)
            checks.append(result(
                f"{character}_{action}_clear_frame_edges",
                not edge_cropped,
                f"edge_cropped_frames={edge_cropped}",
            ))
            if character == "rabbit-worker" and action == "idle":
                pixels = image.load()
                matte_pixels = 0
                for frame in range(2):
                    for y in range(385, 445):
                        for x in range(frame * 512 + 245, frame * 512 + 280):
                            red, green, blue, pixel_alpha = pixels[x, y]
                            if (pixel_alpha > 0 and min(red, green, blue) >= 80
                                    and max(red, green, blue) - min(red, green, blue) <= 45):
                                matte_pixels += 1
                checks.append(result(
                    "rabbit-worker_idle_leg_gap_transparency",
                    matte_pixels == 0,
                    f"neutral_opaque_pixels={matte_pixels}",
                ))
            if character == "business-cat" and action == "sit":
                pixels = image.load()
                eye_boxes = ((200, 150, 232, 187), (250, 150, 288, 187))

                def in_eye_box(x: int, y: int) -> bool:
                    local_x = x % 512
                    return any(left <= local_x < right and top <= y < bottom
                               for left, top, right, bottom in eye_boxes)

                edge_matte_pixels = 0
                for y in range(1, height - 1):
                    for x in range(1, width - 1):
                        red, green, blue, pixel_alpha = pixels[x, y]
                        neutral = (pixel_alpha > 0 and min(red, green, blue) >= 130
                                   and max(red, green, blue) - min(red, green, blue) <= 35)
                        touches_transparency = neutral and any(
                            pixels[nx, ny][3] == 0
                            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
                        )
                        if touches_transparency and not in_eye_box(x, y):
                            edge_matte_pixels += 1
                checks.append(result(
                    "business-cat_sit_white_edge_matte",
                    edge_matte_pixels == 0,
                    f"neutral_edge_pixels={edge_matte_pixels}",
                ))
                eye_white_pixels = []
                for frame in range(2):
                    count = 0
                    for left, top, right, bottom in eye_boxes:
                        for y in range(top, bottom):
                            for x in range(frame * 512 + left, frame * 512 + right):
                                red, green, blue, pixel_alpha = pixels[x, y]
                                if (pixel_alpha > 0 and min(red, green, blue) >= 205
                                        and max(red, green, blue) - min(red, green, blue) <= 35):
                                    count += 1
                    eye_white_pixels.append(count)
                checks.append(result(
                    "business-cat_sit_eye_whites_preserved",
                    all(count >= 70 for count in eye_white_pixels),
                    f"white_pixels_per_frame={eye_white_pixels}",
                ))
            image.close()

    for image in images.values():
        image.close()
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    checks = audit(args.root.resolve())
    payload = {
        "passed": all(check["passed"] for check in checks),
        "checks": checks,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    for check in checks:
        status = "PASS" if check["passed"] else "FAIL"
        print(f"{status} {check['name']}: {check['detail']}")
    return 0 if payload["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
