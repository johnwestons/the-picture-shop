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
        "rabbit": generated / "rabbit-worker-atlas.png",
        "polar": generated / "polar-115-sprite-sheet-clear-table-transparent.png",
        "polar_directions": generated / "polar-cutter-directions-strip.png",
        "empty_pallet": generated / "empty-pallet.png",
        "paper_stack": generated / "paper-stack.png",
        "toolbox_small": generated / "toolbox-small.png",
        "toolbox_large": generated / "toolbox-large.png",
        "paper_boxes": generated / "paper-storage-boxes-strip.png",
        "picture_press": generated / "picture-press-transparent.png",
        "skid_wrapper_directions": generated / "skid-wrapper-directions-strip.png",
        "wrapped_pallet_stages": generated / "wrapped-pallet-stages-strip.png",
        "loading_bay_door": generated / "loading-bay-door-strip.png",
        "delivery_truck": generated / "delivery-truck-open.png",
        "truck_cargo_door": generated / "truck-cargo-door-strip.png",
        "polar_operator_console": generated / "polar-operator-console.png",
        "cutter_control_buttons": generated / "cutter-control-buttons-strip.png",
        "cutter_clamp": generated / "cutter-clamp-strip.png",
        "cutter_blade": generated / "cutter-blade-strip.png",
        "loaded_paper_pallet": generated / "loaded-paper-pallet.png",
        "loaded_paper_pallet_directions": generated / "loaded-paper-pallet-directions-strip.png",
        "pallet_jack": generated / "pallet-jack-directions-strip.png",
        "pallet_jack_loaded": generated / "pallet-jack-loaded-directions-strip.png",
        "vendor_product_pallets": generated / "vendor-product-pallets-atlas.png",
        "boxed_paper_pallet_stages": generated / "boxed-paper-pallet-stages-atlas.png",
        "polar_back_button": generated / "polar-back-button-states-strip.png",
    }
    checks: list[dict[str, object]] = []
    images: dict[str, Image.Image] = {}

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

    rabbit = images.get("rabbit")
    if rabbit:
        width, height = rabbit.size
        checks.append(result("rabbit_grid", width % 6 == 0 and height % 4 == 0, f"size={rabbit.size}"))
        alpha = rabbit.getchannel("A")
        minimum, maximum = alpha.getextrema()
        checks.append(
            result(
                "rabbit_transparency",
                minimum == 0 and maximum >= 250,
                f"alpha_range=({minimum}, {maximum})",
            )
        )
        cell_width, cell_height = width // 6, height // 4
        empty_cells = []
        for row in range(4):
            for column in range(6):
                cell = alpha.crop(
                    (
                        column * cell_width,
                        row * cell_height,
                        (column + 1) * cell_width,
                        (row + 1) * cell_height,
                    )
                )
                if cell.getbbox() is None:
                    empty_cells.append((column + 1, row + 1))
        checks.append(result("rabbit_cells_nonempty", not empty_cells, f"empty_cells={empty_cells}"))

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
        "polar_directions": (2048, 512),
        "polar_operator_console": (1536, 1024),
        "cutter_control_buttons": (512, 128),
        "cutter_clamp": (3840, 512),
        "cutter_blade": (3840, 512),
        "loaded_paper_pallet": (256, 256),
        "loaded_paper_pallet_directions": (1024, 256),
        "pallet_jack": (1024, 256),
        "pallet_jack_loaded": (1024, 256),
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
        "polar_back_button": ((2172, 724), 3, 1),
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
        "tan-cat": {"idle": 2, "walk": 3, "sit": 2},
        "green-blazer-cat": {"idle": 2, "walk": 3, "sit": 2, "use": 3},
        "blue-coaler-cat": {"idle": 2, "walk": 3, "sit": 2},
        "business-dragon": {"idle": 2, "walk": 4, "sit": 2},
        "business-fox": {"idle": 2, "walk": 4, "sit": 2},
        "business-cat": {"idle": 2, "walk": 4, "sit": 2},
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
