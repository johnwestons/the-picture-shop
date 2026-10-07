"""Normalize immutable generated art and precompute the shared grip contract."""
from pathlib import Path
import json
import math
import hashlib
import numpy as np
from PIL import Image, ImageDraw
from build_pallet_jack_assets import largest_component

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/pallet-jack-motion-v2"
DEST = ROOT / "assets/generated/pallet-jack-motion-v2"
REVIEW = ROOT / "output/pallet-jack-motion-v2"
SIZE = 256
ORIGIN = (128, 164)
DIRECTIONS = ["east", "northeast", "north", "southeast", "south"]


def clean(image):
    # Only disconnected generation specks are removed. Pale fur is retained.
    result = largest_component(image)
    if not result.getbbox():
        raise ValueError("Empty source cell")
    return result


def grid(path):
    source = Image.open(path).convert("RGBA")
    return [clean(source.crop((round(col * source.width / 4), round(row * source.height / 4),
                               round((col + 1) * source.width / 4), round((row + 1) * source.height / 4))))
            for row in range(4) for col in range(4)]


def hands(frame, direction):
    rgba = np.array(frame).astype(float)
    r, g, b, a = [rgba[:, :, i] for i in range(4)]
    yy, xx = np.indices(r.shape)
    bounds = frame.getbbox()
    top, bottom = bounds[1], bounds[3]
    mask = (a > 90) & (r > g * 1.24) & (g > b * 1.1) & (g > 55)
    mask &= (yy > top + (bottom - top) * .39) & (yy < top + (bottom - top) * .64)
    if direction in ("east", "northeast", "southeast"):
        mask &= xx > 150
    elif direction == "north":
        # Rear-view palms sit beyond the torso and are occluded by the body.
        return {"x": 128, "y": round(top + (bottom - top) * .47, 2)}
    if not mask.any():
        raise ValueError(f"Missing hand anchor for {direction}")
    return {"x": round(float(np.mean(xx[mask])), 2), "y": round(float(np.mean(yy[mask])), 2)}


def strip(frames, name, columns=None):
    columns = columns or len(frames)
    image = Image.new("RGBA", (SIZE * columns, SIZE * math.ceil(len(frames) / columns)))
    for index, frame in enumerate(frames):
        image.alpha_composite(frame, (SIZE * (index % columns), SIZE * (index // columns)))
    image.save(DEST / f"{name}.png")
    return image


def normalize_worker(cells):
    bounds = [cell.getbbox() for cell in cells]
    scale = 218 / max(box[3] - box[1] for box in bounds)
    result = []
    for cell, box in zip(cells, bounds):
        # One scale per strip. Floor alignment removes sheet-placement jitter;
        # neither limb phase nor body identity is altered by normalization.
        body = cell.crop(box)
        body = body.resize((round(body.width * scale), round(body.height * scale)), Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (SIZE, SIZE))
        frame.alpha_composite(body, (128 - body.width // 2, 235 - body.height))
        result.append(frame)
    return result


def lua(value):
    if isinstance(value, dict):
        return "{" + ",".join(f'["{key}"]={lua(item)}' for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return str(value)


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    data = {"originX": ORIGIN[0], "originY": ORIGIN[1], "frames": [], "hands": {}, "anchors": {}, "metrics": {}}
    animations = {}
    neutral = {}
    for direction in DIRECTIONS:
        action = "push" if direction == "east" else "push_" + direction
        frames = normalize_worker(grid(SOURCE / f"push_{direction}.png"))
        # Existing two-foot neutral drawings remain the directional idle. The
        # source strips are immutable, and the new cycles live separately.
        old = Image.open(ROOT / f"assets/source/warehouse-expansion-v1/pallet-jack-push/push-{direction}-v1-candidate.png")
        idle = normalize_worker([clean(old.crop((i * 512, 0, (i + 1) * 512, 512))) for i in (1, 5)])
        for name, items, role in ((action, frames, "gait"), (action + "_idle", idle, "directional_idle")):
            strip(items, name)
            data["hands"][name] = [hands(f, direction) for f in items]
            data["anchors"][name] = [{"x": 128, "y": 235} for _ in items]
            data["metrics"][name] = [list(f.getbbox()) for f in items]
            animations[name] = {"path": f"assets/generated/pallet-jack-motion-v2/{name}.png",
                                "frame_width": SIZE, "frame_height": SIZE, "frame_count": len(items),
                                "role": "subdivided_gait" if role == "gait" else role, "loop": True, "fps": 22.4 if role == "gait" else .65}
        core_name = action + "_core"
        core = Image.new("RGBA", (SIZE * 8, SIZE))
        for i, frame in enumerate(frames[::2]):
            core.alpha_composite(frame, (i * SIZE, 0))
        core.save(REVIEW / f"{core_name}.png")
        animations[core_name] = {"path": f"output/pallet-jack-motion-v2/{core_name}.png",
                                 "frame_width": SIZE, "frame_height": SIZE, "frame_count": 8,
                                 "role": "gait", "loop": True, "fps": 11.2}
        neutral[action] = (data["hands"][action + "_idle"][0], max(b[3] - b[1] for b in data["metrics"][action + "_idle"]))
        contact = Image.new("RGBA", (SIZE * 4, (SIZE + 22) * 4), (28, 33, 39, 255))
        draw = ImageDraw.Draw(contact)
        for i, frame in enumerate(frames):
            x, y = i % 4 * SIZE, i // 4 * (SIZE + 22)
            contact.alpha_composite(frame, (x, y))
            draw.text((x + 8, y + SIZE + 3), f"{direction} phase {i + 1:02}", fill="white")
        contact.save(REVIEW / f"{action}-contact.png")
        frames[0].save(REVIEW / f"{action}.gif", save_all=True, append_images=frames[1:], duration=45, loop=0, disposal=2)

    # Reviewed ground-center and grip landmarks on the source turntable cells.
    pivots = [(190,220),(183,231),(179,223),(186,241),(172,229),(157,235),(155,238),(161,253),
              (167,227),(179,218),(168,204),(176,164),(176,147),(167,157),(169,193),(178,215)]
    grips = [(94,67),(105,92),(99,79),(111,60),(174,52),(213,75),(224,87),(229,108),
             (251,95),(212,125),(237,124),(244,132),(174,123),(111,124),(119,142),(90,150)]
    views = [("push",1),("push_southeast",1),("push_south",1),("push_southeast",-1),
             ("push",-1),("push_northeast",-1),("push_north",1),("push_northeast",1)]
    jack_frames, loaded_frames = [], []
    pallet_source = Image.open(ROOT / "assets/generated/loaded-paper-pallet-directions-strip.png").convert("RGBA")
    extra_pivots = [(188,220),(183,228),(181,243),(181,243),(162,229),(157,235),(154,238),(160,251),
                    (163,225),(178,219),(168,207),(176,163),(176,147),(168,160),(170,194),(176,215)]
    extra_grips = [(96,86),(112,94),(119,75),(138,61),(181,52),(213,88),(226,88),(247,91),
                   (248,125),(213,143),(242,128),(242,140),(179,123),(106,134),(119,148),(91,158)]
    base_cells = grid(SOURCE / "jack-turns.png")
    between_cells = grid(SOURCE / "jack-turns-between.png")
    cells = [cell for pair in zip(base_cells, between_cells) for cell in pair]
    for i, cell in enumerate(cells):
        scale = .69 * base_cells[0].width / cell.width
        body = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.Resampling.LANCZOS)
        px, py = (pivots if i % 2 == 0 else extra_pivots)[i // 2]
        position = (round(ORIGIN[0] - px * scale), round(ORIGIN[1] - py * scale))
        frame = Image.new("RGBA", (SIZE, SIZE))
        frame.alpha_composite(body, position)
        grip = (grips if i % 2 == 0 else extra_grips)[i // 2]
        hx, hy = position[0] + grip[0] * scale - ORIGIN[0], position[1] + grip[1] * scale - ORIGIN[1]
        angle = i * math.pi / 16
        phase = i / 4
        v, blend = math.floor(phase) % 8, phase % 1
        offsets = []
        for j in (v, (v + 1) % 8):
            action, mirror = views[j]
            grip, height = neutral[action]
            s = .3 * 256 / height / .416
            offsets.append(((grip["x"] - 128) * s * mirror, (grip["y"] - 235) * s))
        ox = hx - (offsets[0][0] * (1 - blend) + offsets[1][0] * blend)
        oy = hy - (offsets[0][1] * (1 - blend) + offsets[1][1] * blend)
        data["frames"].append({"handleX": round(hx,2), "handleY": round(hy,2),
                               "operatorX": round(ox,2), "operatorY": round(oy,2),
                               "loadX": round(math.cos(angle) * 24,2), "loadY": round(math.sin(angle) * 14,2)})
        jack_frames.append(frame)
        loaded = frame.copy()
        pallet_index = [3,3,3,3,3,2,2,2,2,0,0,0,0,1,1,1][i // 2]
        pallet = pallet_source.crop((pallet_index * SIZE, 0, (pallet_index + 1) * SIZE, SIZE)).resize((112,112), Image.Resampling.LANCZOS)
        loaded.alpha_composite(pallet, (72 + round(math.cos(angle)*24), 77 + round(math.sin(angle)*14)))
        loaded_frames.append(loaded)
    # Jack art is under 110 screen pixels wide; 192px cells keep 32 views
    # sharp without raising startup texture memory above the game's cap.
    for name, frames in (("jack-turns", jack_frames), ("jack-loaded-turns", loaded_frames)):
        atlas = strip(frames, name, 16)
        atlas.resize((3072,384), Image.Resampling.LANCZOS).save(DEST / f"{name}.png")
    for name in ("jack-turns", "jack-loaded-turns"):
        atlas = Image.open(DEST / f"{name}.png")
        hashes = set()
        for i in range(32):
            cell = atlas.crop(((i % 16) * 192, (i // 16) * 192, (i % 16 + 1) * 192, (i // 16 + 1) * 192))
            bounds = cell.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
            if not bounds or min(bounds[:2]) < 2 or max(bounds[2:]) > 190:
                raise ValueError(f"{name} frame {i + 1} is empty or clipped: {bounds}")
            hashes.add(hashlib.sha256(cell.tobytes()).hexdigest())
        if len(hashes) != 32:
            raise ValueError(f"{name} contains duplicate turn drawings")
    data["originX"] *= .75
    data["originY"] *= .75
    for pose in data["frames"]:
        for key in pose:
            pose[key] = round(pose[key] * .75, 4)
    data_path = ROOT / "src/pallet_jack_art.lua"
    data_path.write_text("-- Generated by tools/build_pallet_jack_motion_v2.py; immutable-source grip landmarks.\nreturn " + lua(data) + "\n", encoding="utf-8")
    (REVIEW / "grip-contract.json").write_text(json.dumps(data, indent=2))
    directions = {}
    for direction, action, mirror in [("east","push",False),("southeast","push_southeast",False),("south","push_south",False),
                                      ("southwest","push_southeast",True),("west","push",True),("northwest","push_northeast",True),
                                      ("north","push_north",False),("northeast","push_northeast",False)]:
        directions[direction] = {"walk_animation":action + "_core", "idle_animation":action + "_idle", "mirror_x":mirror}
    spec = {"version":1,"character":"rabbit-pallet-jack","animations":animations,"directions":directions,
            "runtime_subdivision": {"frames_per_pose":2,"pixels_per_drawing":5,"cycle_distance":80},
            "gait":{"pose_order":["left_contact","left_down","right_passing","right_up","right_contact","right_down","left_passing","left_up"],
                    "pixels_per_frame":10,"base_speed":112,"speed_multipliers":[.96,.94,1.04,1.06]*2,
                    "acceleration_multipliers":[.92,.90,1.08,1.10]*2},
            "audit":{"alpha_threshold":40,"edge_margin":2,"detached_component_ratio":.003,"baseline_tolerance":3,"center_tolerance":20}}
    (ROOT / "character-motion/rabbit-pallet-jack.json").write_text(json.dumps(spec,indent=2)+"\n")
    records = []
    for path in sorted(SOURCE.glob("*.png")):
        records.append({"path":path.relative_to(ROOT).as_posix(),
                        "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                        "size":list(Image.open(path).size)})
    manifest = {
        "version":2, "generator":"built-in image_gen", "source_policy":"immutable",
        "prompt_record":"Summaries, not verbatim generation prompts",
        "reference_jack":"output/pallet-jack-directions-preview.png",
        "reference_worker":"assets/source/warehouse-expansion-v1/pallet-jack-push/push-{direction}-v1-candidate.png",
        "worker_prompt_summary":"Exact reference rabbit/camera, gray shirt and blue overalls; 16 distinct contact/load/passing/knee-up poses as a 4x4 transparent grid; stationary paired hands, common scale and floor baseline; no actual jack, matte, shadows or labels.",
        "jack_prompt_summary":"Rigid yellow hydraulic jack, charcoal forks/wheels and triangular black grip; 16 clockwise yaw views in a 4x4 transparent grid, with a second 16-view generation offset halfway between the first views. Match the same camera and identity with complete machine silhouettes.",
        "western_worker_views":"intentional mirrors of east, northeast and southeast reference views",
        "runtime":"32 jack views in a 16x2 atlas of 192px cells; five authored 16-frame push strips with western mirrors; original planted neutral frames normalized into five two-frame idles",
        "sources":records,
    }
    (SOURCE / "source-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    print("Built 32 turn views, 80 gait drawings, 10 planted idle drawings and shared grip metadata.")


if __name__ == "__main__":
    main()
