"""Build a staged 16-drawing walk cycle for the cat worker.

This builder reads immutable approved source strips and selected built-in
ImageGen sheets. It writes only the isolated Luna source/output staging paths.
It does not register or promote the art into runtime game assets.
"""
from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import json
import shutil

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "assets/source/animation-overhaul-luna-v1/cat-worker"
OUTPUT = ROOT / "output/animation-overhaul/luna-cat"
GENERATED_ROOT = Path(r"C:\Users\johnw\.codex\generated_images\01a17bf6-4592-76b2-9ffc-934be2409a07")

SOURCE_STRIPS = {
    "north": "assets/source/cat-worker-v1/locomotion/walk_north.png",
    "northeast": "assets/source/cat-worker-v1/locomotion/walk_northeast.png",
    "east": "assets/source/cat-worker-v1/locomotion/walk.png",
    "southeast": "assets/source/cat-worker-v1/locomotion/walk_southeast.png",
    "south": "assets/source/cat-worker-v1/locomotion/walk_south.png",
    "southwest": "assets/source/cat-worker-v1/locomotion/walk_southwest.png",
    "west": "assets/source/cat-worker-v1/locomotion/walk_west.png",
    "northwest": "assets/source/cat-worker-v1/locomotion/walk_northwest.png",
}
RUNTIME_STRIPS = {
    "north": "assets/generated/characters/cat-worker/walk_north.png",
    "northeast": "assets/generated/characters/cat-worker/walk_northeast.png",
    "east": "assets/generated/characters/cat-worker/walk.png",
    "southeast": "assets/generated/characters/cat-worker/walk_southeast.png",
    "south": "assets/generated/characters/cat-worker/walk_south.png",
    "southwest": "assets/generated/characters/cat-worker/walk_southwest.png",
    "west": "assets/generated/characters/cat-worker/walk_west.png",
    "northwest": "assets/generated/characters/cat-worker/walk_northwest.png",
}
GENERATIONS = {
    "north": "exec-e43acabc-2b33-4ccc-9c23-bf79fddf46c8.png",
    "east": "exec-e992d26c-b581-40de-9614-8f6e08aea104.png",
    "northeast": "exec-4c508303-122d-44ae-9994-120ed72e0f80.png",
    "south": "exec-6b29bc9c-fa15-43c7-8d70-2b6c02ab7c95.png",
    "southeast": "exec-07e715f4-13f6-4f85-82c5-32fb47356f3f.png",
    "southwest": "exec-f899c36c-b96c-4c9e-85c1-02146b348690.png",
    "west": "exec-8e330880-99ce-4ae0-8972-9460c1230722.png",
    "northwest": "exec-0e2546a0-d9b8-4e6b-9509-dcc3a2b26f01.png",
}
DIRECTIONS = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
PHASES = [
    "left_contact", "left_weight_down", "right_passing", "right_knee_up",
    "right_contact", "right_weight_down", "left_passing", "left_knee_up",
]
CANONICAL_ROLE_AUDIT = {
    "north": {"confidence": "low", "finding": "Rear-facing feet are substantially occluded. The 1/5 contact and 3/7, 4/8 swing-role pairs are not visually reliable enough to assign; preserve originals pending root review.", "corrected_canonical_replacement_staged": False},
    "northeast": {"confidence": "medium-low", "finding": "Three-quarter rear view partially occludes the boots. No opposite-foot ownership failure can be stated confidently from the current contact preview; preserve originals pending root review.", "corrected_canonical_replacement_staged": False},
    "east": {"confidence": "medium-high", "finding": "Profile source keys 1/5 appear to reuse the same near-side planted boot; pairs 3/7 and 4/8 also appear to repeat the visible near-side swing role. Needs corrected base review before transition quality can be accepted.", "corrected_canonical_replacement_staged": False},
    "southeast": {"confidence": "medium-low", "finding": "Three-quarter front view shows leg motion, but satchel and body overlap obscure enough foot ownership that a canonical role defect is not confirmed; preserve originals pending root review.", "corrected_canonical_replacement_staged": False},
    "south": {"confidence": "high", "finding": "Frontal source keys 1 and 5 both visibly plant the picture-left boot. Source keys 3/7 and 4/8 also appear to reuse the same side's passing and knee-up roles. A corrected eight-key candidate now alternates opposite contact feet and is staged separately; original master remains immutable.", "corrected_canonical_replacement_staged": True},
    "southwest": {"confidence": "medium-low", "finding": "Three-quarter front view shows some foot separation but bag/tunic overlap makes opposite-foot ownership uncertain; preserve originals pending root review.", "corrected_canonical_replacement_staged": False},
    "west": {"confidence": "medium-high", "finding": "Profile source keys 1/5 appear to reuse the same near-side planted boot; pairs 3/7 and 4/8 also appear to repeat the visible near-side swing role. Needs corrected base review before transition quality can be accepted.", "corrected_canonical_replacement_staged": False},
    "northwest": {"confidence": "low", "finding": "Rear three-quarter view partly hides both boots under satchel/tunic; opposite-foot ownership is ambiguous and no replacement is selected.", "corrected_canonical_replacement_staged": False},
}
TARGET_SIZE = 512
BASELINE = 458  # Exclusive bottom bound; the last opaque source row is 457.


PROMPTS = {
    "north": '''Use case: stylized-concept
Asset type: transparent pixel-art in-between pose sheet for a 2D game animation
Input images: Image 1: approved cat-worker north-facing eight-phase walk strip; use it as the exact character identity, clothing, palette, scale and pose-cycle reference.
Primary request: create eight genuinely new, coherent in-between drawings for the same cat-worker, viewed from directly north/back, to interleave between the eight canonical drawings in Image 1. Arrange as a clean 4-column by 2-row contact sheet of eight separate square frames, each with one complete cat centered and generous clear margins. No gaps, frames, separators, labels, numbers or text; only transparent space between cells. Transparent background.
Subject: small upright anthropomorphic charcoal-black cat warehouse worker wearing the same olive-green scarf tied at the back, orange-brown work jacket, brown tool satchel with the same visible pouch and tools, dark trousers and dark work boots as Image 1. Preserve the exact rear-facing north view; retain the original cat proportions and pixel-art treatment. Exactly two ears, two arms, two legs and one tail. Keep the scarf knot, shoulder strap, satchel, pouch and tail on their existing body sides. No hand-held extra props.
Pose order, read left-to-right then top-to-bottom. These are transition drawings between consecutive canonical frames, not replacement key poses: (1) between original left-contact and left-weight-down: soften the left planted leg into early loading while the right foot swings through; (2) between left-weight-down and right-passing: the body settles slightly and the right foot passes close beneath the hips; (3) between right-passing and right-knee-up: the right knee rises into propulsion as the left leg supports; (4) between right-knee-up and right-contact: carry the lifted right foot forward, nearly reaching contact; (5) between right-contact and right-weight-down: transfer weight gradually onto the right foot; (6) between right-weight-down and left-passing: the left foot releases and passes close beneath the hips; (7) between left-passing and left-knee-up: raise the left knee into propulsion while the right leg supports; (8) between left-knee-up and the next cycle's left-contact: carry the lifted left foot forward to the instant before its full contact.
Constraints: preserve the eight-phase cycle and fixed stride distance; transitions have intermediate motion and must not duplicate any canonical drawing. Clearly alternate left/right leg roles. Keep the planted foot at the original ground baseline when that leg is supporting; show only a slight natural torso rise/fall. Keep body center, sprite scale, palette, outline, lighting, clothing, all exact identity details stable and consistent with Image 1. Keep the tail anatomically attached and naturally counterbalancing, without flipping it or changing its stripe/color. Pixel art with crisp hand-painted pixels and the same thick dark outline as the reference. Avoid: extra/missing ears, limbs, tails, paws, duplicate characters, front or side view, mirrored view, swapped clothing or pouch side, changed worker gear, different fur color, blank or soft blurry designs, shadows, checkerboard, scenery, grid lines, panel dividers, visual captions, or watermark.''',
    "east": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved east-facing cat-worker walk cycle with eight canonical poses. It is the only identity, outfit, palette, scale, camera, lighting and direction reference.
Primary request: create exactly eight different in-between walk drawings of the same upright anthropomorphic charcoal-black cat worker, facing right/east in profile. They will be interleaved between the existing eight canonical drawings. Place them on a transparent 4-column by 2-row sheet, read left to right then top to bottom; each panel is a square frame containing one complete character, centered at the same scale and foot anchor as Image 1. No panel borders or labels.
Subject details: exactly two ears, two arms, two legs and one attached tail; yellow olive scarf knotted at the left/back side of neck, orange-brown work jacket, visible cross-body strap, brown orange tool satchel with round silver clasp on the same hip, small work tools and dark boots/trousers exactly as Image 1. Keep the eye and muzzle profile facing east. Preserve which arm is in front and which hand/tool equipment is shown; do not mirror or flip any silhouette details.
Read each panel as an intermediate between adjacent original phases: 1. between left contact and left weight-down, left boot still planted as weight just begins to sink, right leg swings slightly forward. 2. between left weight-down and right passing, gentle sink continues while right paw approaches under the pelvis. 3. between right passing and right knee-up, right leg crosses under the hips and begins rising, left leg supports. 4. between right knee-up and right contact, lifted right knee extends forward, boot nearly reaches floor. 5. between right contact and right weight-down, transfer weight to newly planted right boot. 6. between right weight-down and left passing, left boot lifts and moves under the body. 7. between left passing and left knee-up, left knee bends and rises while right supports. 8. between left knee-up and next left contact, lifted left boot reaches forward just before landing. Match gait path length from Image 1; retain a supporting boot at the baseline and keep pelvis over the support leg. Tail sways only subtly as counterbalance, attached to the pelvis.
Style: faithfully match the reference's small hand-painted pixel art, softly textured fur, crisp dark purple-black outline, warm upper-left light and subdued orange/olive palette. Transparent canvas with no drawn background, no shadow and no ground. No new key poses, no duplicated stances, no body shift masquerading as motion. Preserve character size and body center through all eight panels. Avoid extra or missing appendages, changed anatomy, changed clothing, swapped tool side, different cat, mirrored art, second character, blurry rendering, checkerboard, scenery, panel borders, text, numbers or watermark.''',
    "northeast": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved cat-worker northeast-facing eight-phase walk strip. Use it as the only reference for identity, angle, clothes, proportions, palette, lighting, outline, tail and stride.
Primary request: create eight genuinely different intermediate drawings of this same upright charcoal-black cat worker, viewed from the exact northeast/back three-quarter angle, walking diagonally toward upper-right. Arrange exactly eight square character cells as 4 columns by 2 rows, top row left-to-right first, then bottom row, on true transparent background. Each cell contains only one full-body cat centered consistently. No labels or visible panel lines.
Anatomy and identity: exactly two triangular ears, two arms, two legs, one tail attached at the pelvis. Preserve the one visible yellow eye/side of head, the scarf knot at the back, olive-yellow scarf, orange-brown jacket with dark sleeve bands, diagonal shoulder strap, brown tool satchel with clasp and its left/back hip placement, dark olive trousers and dark boots. Keep the back-three-quarter view and the tail curling to the same side shown in Image 1. Do not mirror or swap any asymmetric gear.
The eight drawings are transitions between consecutive canonical poses in Image 1, not replacement key poses: 1. left-contact to left-down, left boot planted, begin loading, right foot begins swing; 2. left-down to right-passing, compress slightly, right foot passes under hips; 3. right-passing to right-knee-up, right knee lifts as left supports; 4. right-knee-up to right-contact, right boot reaches diagonally forward just before floor contact; 5. right-contact to right-down, transfer support to right boot; 6. right-down to left-passing, left boot releases and passes beneath the body; 7. left-passing to left-knee-up, lift the left knee while right supports; 8. left-knee-up to next left-contact, carry left boot toward its landing. Use the same modest stride length as Image 1.
Preserve body scale and center, sprite-cell framing, baseline, leg thickness, scarf, strap, bag, lighting direction (warm light upper-left), palette and dark pixel outline from Image 1. Supporting boot stays at original floor line; only natural small body bob and tail counter-sway. Crisp small hand-painted pixel art, no soft blur. Avoid: added/missing body parts, third ear, extra legs/tails, duplicate stances, standing still, exaggerated running, changed camera, mirrored character, different tools/clothing, background, ground/shadow, checkerboard, labels, borders, grid or watermark.''',
    "south": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved south-facing cat-worker walk cycle. Use it as the exact character, frontal camera view, asymmetric equipment placement, style and cycle reference.
Primary request: create exactly eight useful, distinct in-between poses to interleave between the canonical eight frames of Image 1. Make a transparent 4-column by 2-row contact sheet, reading left-to-right then top-to-bottom, with one complete centered character in each equal square panel. No panel borders, labels, frames or text.
Subject: the same small upright charcoal-black anthropomorphic cat worker, facing straight toward the camera in the same south view as Image 1, with both gold eyes, two triangular ears, two arms, two legs and one attached tail. Keep the olive-yellow scarf, orange-brown jacket, dark sleeve bands, brown cross-body strap, tool satchel and clasp on the exact same side as the south reference (do not mirror), dark olive work trousers and boots. Preserve face, head size, body scale, line quality, lighting and palette.
In-between order: 1. between left contact and left weight-down, keep left boot planted and begin loading as right foot swings; 2. between left-down and right-passing, slight weight compression with right foot passing under hips; 3. between right-passing and right-knee-up, right knee begins rising while left supports; 4. between right-knee-up and right-contact, extend that boot toward ground; 5. between right-contact and right-down, gradually transfer weight onto right boot; 6. between right-down and left-passing, release left boot under body; 7. between left-passing and left-knee-up, raise left knee while right supports; 8. between left-knee-up and next left-contact, bring left boot forward almost to landing. Use the same restrained stride length as the reference and do not make the gait a run. The grounded leg's foot touches the original floor line in every pose; maintain a narrow, believable walking base with natural counter-swinging arms.
Match the source's pixel-painted illustration and thick dark violet-brown outline, upper-left warm light, fur and fabric texture, scarf folds, strap, bag shape and tools. Keep the body center and frame scale steady, with only slight vertical gait bob. Keep tail anatomically attached and on the same side. No mirrored design. Avoid: extra/missing appendages, more than two ears, third arm, extra leg/tail, changing eye count, swapping the bag or strap side, changing gear, shifting the body to fake motion, duplicated/standing poses, blurry art, background, shadows, checkerboard, scenery, grid borders, numbering, captions or watermark.''',
    "southeast": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved cat-worker southeast-facing eight-pose walk strip. Match it exactly for character identity, rear/front visibility, camera, asymmetrical satchel side, palette and light.
Primary request: produce eight distinct intermediate walk drawings to insert between the eight existing canonical poses. Arrange eight separate equal square frames on a transparent 4-column × 2-row sheet, reading left to right, top row then bottom row; one complete character per cell, centered with even scale and foot anchor. No text or dividers.
Character: small upright charcoal-black cat worker, facing diagonally down-right/southeast in the exact same three-quarter angle as Image 1. Exactly 2 ears, 2 arms, 2 legs, 1 tail. Keep the eye visibility and cheek profile, olive-yellow neck scarf and back knot, orange-brown jacket with dark bands, cross-body strap, brown-orange tool bag and clasp on the same hip, dark olive work trousers and boots. Retain all sides as shown; never mirror or flip.
Pose progression: cell 1 left-contact→left-weight-down: left support foot planted, body starts loading, right foot starts to swing. Cell 2 left-down→right-passing: a slight compress, right foot passes beneath hips. Cell 3 right-passing→right-knee-up: right knee starts lifting, left leg supports. Cell 4 right-knee-up→right-contact: extend right boot diagonally toward the floor, not yet planted. Cell 5 right-contact→right-down: transfer weight to the new right support. Cell 6 right-down→left-passing: release left boot and pass it under body. Cell 7 left-passing→left-knee-up: left knee rises while right supports. Cell 8 left-knee-up→next left-contact: left boot travels toward landing. These are midpoints between canonical poses, not replacement key poses, and retain the same compact stride distance from Image 1. Alternating legs must be clear.
Match Image 1's cell scale, body center, foot baseline, pixel-painted texture, dark violet-brown outline, warm upper-left lighting, restrained palette and proportions. Preserve a planted support boot at the same ground line; only natural small torso bob and tail counterbalance. Keep the tail attached and on the same side. Avoid: extra/missing appendages, altered eyes/face, extra ear/limb/tail, swapped clothes/tools, mirrored view, large jumps, duplicated poses, scenery, background, shadows, checkerboard, labels, grid lines, panel borders or watermark.''',
    "southwest": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved southwest-facing cat-worker walk strip. Use it as the only exact identity and view reference.
Primary request: create eight new intermediate walk drawings of the same cat, to interleave between the original eight phases. Arrange in an 8-cell transparent contact sheet, 4 square columns × 2 rows, reading row-major. One complete centered character per cell; no labels, frame borders or dividers.
Keep the same upright charcoal-black cat viewed at the exact southwest/front three-quarter angle walking diagonally down-left, matching the reference's visible eye(s), body proportions, scarf folds, satchel orientation and tail. Exactly two ears, two arms, two legs and one tail. The olive-yellow scarf knots at the back/near shoulder as shown; orange-brown jacket and dark sleeve bands; orange-brown cross-body tool satchel with round clasp and its same hip/shoulder strap positions; dark olive trousers, work boots. Do not mirror the view or change sides of the asymmetric strap, satchel, clasp, tools, tail or visible limbs.
Eight transition midpoint beats from the reference's original stride: 1 left contact→left loading, left foot planted and right begins swinging; 2 left loading→right passing, small compression with right foot beneath pelvis; 3 right passing→right knee lift, right leg begins its upward swing; 4 right knee lift→right contact, right boot reaches forward toward the floor; 5 right contact→right loading, transfer weight onto right support; 6 right loading→left passing, left foot moves beneath body; 7 left passing→left knee lift, left knee bends upward with right supporting; 8 left knee lift→next left contact, left boot advances almost to the ground. Use the same compact walk stride, no run or bound.
Match Image 1’s scale, center, foot baseline, pixel-painted texture, warm light from upper left, dark purple-brown outline and subdued palette. Keep one planted boot at the original baseline, natural small torso bob and same tail attachment with restrained counter-sway. New drawings must visibly show intermediate leg motion, not static repeats or simple body shifts. Avoid any extra or missing anatomical parts, background, floor, shadow, checkerboard, panel lines, labels, numbers or watermark.''',
    "west": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved cat-worker west-facing walk cycle, the exact backward-running left-facing profile reference for this worker.
Primary request: make exactly eight new midpoint drawings to interleave between the original eight canonical phases, in a transparent 4×2 sheet of equal square cells, read row-major. One whole character in each cell, with no labels, borders, grid or background.
Keep the same upright charcoal-black cat in exact west-facing profile, moving toward screen-left. Preserve the direction and exact asymmetric details in Image 1: two triangular ears, two arms, two legs, one attached tail; olive-yellow scarf knotted at back/right as pictured; orange-brown jacket with dark bands, cross-body strap and brown tool bag/clasp on the same hip and side; dark olive trousers and boots; same eye and muzzle facing left. Never mirror or swap hands, bag, strap, tools or tail. Maintain small body scale, center, floor baseline, pixel-painted texture, thick dark violet-brown outline, upper-left warm light and original colors.
Pose cells are transitions between reference phases: 1 left contact→left loading (left support paw remains planted, right leg starts forward swing), 2 left loading→right passing (sink modestly, right paw passes below pelvis), 3 right passing→right knee rising (left supports), 4 right knee rising→right contact approach (reach the right boot forward short of floor), 5 right contact→right loading (settle onto new right support), 6 right loading→left passing, 7 left passing→left knee rising, 8 left knee rising→next left contact approach. Use the same compact stride distance and alternating legs as Image 1. Keep the support boot at the original baseline; only a small natural torso bob and subtle tail counter-swing. Each pose must visibly progress the legs and not be a repeated standing pose or body translation.
Style: match the reference's crisp hand-painted pixel art exactly, with restrained detail and no blur. Avoid: missing/extra anatomy, extra ear/leg/arm/tail, multiple cats, changed clothes or pouch side, swapped hands/equipment, flipped view, exaggerated run, background, shadow, ground, checkerboard, panel separators, labels, numbers, text or watermark.''',
    "northwest": '''Use case: stylized-concept
Asset type: transparent 2D game sprite animation transitions
Input image: Image 1 is the approved cat-worker northwest-facing eight-pose walk strip, the only reference for identity, camera angle, direction, clothing, palette, lighting and stride.
Primary request: generate exactly eight genuinely new intermediate drawings for interleaving between the original eight canonical northwest frames. Arrange a row-major 4-column × 2-row sheet of eight square transparent cells, one complete centered cat per cell. No cell borders, separators, labels, numbers or other text.
Same upright charcoal-black anthropomorphic cat worker viewed diagonally upper-left/northwest from the exact back three-quarter angle in Image 1, with precisely two ears, two arms, two legs and a single tail attached at the pelvis. Preserve this view’s visible eye/profile, olive-yellow scarf tied behind the neck, orange-brown jacket with dark sleeve bands, cross-body strap, brown tool satchel with clasp and gear on the same shoulder/hip sides as the reference, dark olive trousers and work boots. Retain its tail side and shape as shown. No mirroring.
Pose sequence: new transition midpoints, not replacements: (1) left contact to left weight-down, left boot planted while the right leg begins swinging; (2) left down to right passing, small compression as right foot passes under hips; (3) right passing to right knee-up, right knee lifts with left support; (4) right knee-up to right contact, right boot reaches northwest just above floor; (5) right contact to right down, transfer weight to right foot; (6) right down to left passing, left boot releases and passes under body; (7) left passing to left knee-up, left knee rises while right supports; (8) left knee-up to next left contact, bring left boot toward landing. Use the exact modest cycle and stride length from Image 1. Show an alternating support/swing leg at each step and keep the support boot at the same baseline.
Match the reference’s stable body size and center, foot anchor, crisp hand-painted pixel art, thick dark outline, upper-left warm light and subdued colors. Natural small torso bob only, plus slight tail counterbalance. Transparent background. Avoid any anatomy errors or extras, standing duplicates, shift-only fake movement, pose duplication, altered clothes, swapped equipment, changed direction, mirrored character, scenery, ground, shadow, checkerboard, panel borders, gridlines, labels or watermark.''',
}


def file_hash(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def occupied_bbox(im: Image.Image):
    mask = im.getchannel("A").point(lambda value: 255 if value >= 16 else 0)
    return mask.getbbox()


def split_generated_sheet(sheet: Image.Image):
    x_edges = [(i * sheet.width) // 4 for i in range(5)]
    y_edges = [(i * sheet.height) // 2 for i in range(3)]
    cells = []
    for row in range(2):
        for col in range(4):
            cell = sheet.crop((x_edges[col], y_edges[row], x_edges[col + 1], y_edges[row + 1]))
            bbox = occupied_bbox(cell)
            if bbox is None:
                raise ValueError(f"Empty generated cell at row={row}, column={col}")
            cells.append((cell, bbox))
    return cells


def torso_axis_x(im: Image.Image) -> float:
    """Estimate the body axis from the median center of torso-band alpha runs."""
    mask = im.getchannel("A").point(lambda value: 255 if value >= 16 else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("Cannot find torso axis in empty image")
    y0, y1 = bbox[1], bbox[3]
    band_start = max(0, round(y0 + 0.30 * (y1 - y0)))
    band_end = min(im.height, round(y0 + 0.75 * (y1 - y0)))
    centers = []
    for y in range(band_start, band_end):
        pixels = list(mask.crop((0, y, im.width, y + 1)).get_flattened_data())
        runs = []
        start = None
        for x, value in enumerate(pixels + [0]):
            if value and start is None:
                start = x
            elif not value and start is not None:
                runs.append((start, x))
                start = None
        if runs:
            left, right = max(runs, key=lambda run: run[1] - run[0])
            if right - left >= 12:
                centers.append((left + right) / 2)
    if not centers:
        raise ValueError("Could not estimate torso axis from alpha runs")
    centers.sort()
    return centers[len(centers) // 2]


def transformed_transition_cells(cells, canonical_frames):
    """Use one scale per direction and rigid torso/ground-anchor translations.

    The generated 4x2 sheets contain local panel-placement jitter. Every
    complete cell receives the same direction-wide scale, then rigidly aligns
    its torso axis to the neighboring source-key midpoint and its planted boot
    to the source ground line. Translation preserves size and body height
    relative to the planted foot; poses are never independently resized,
    warped or cropped to alpha bounds.
    """
    generated_boxes = [bbox for _, bbox in cells]
    canonical_boxes = [occupied_bbox(frame) for frame in canonical_frames]
    canonical_anchors = [bottom_row_anchor(frame) for frame in canonical_frames]
    generated_heights = [b[3] - b[1] for b in generated_boxes]
    canonical_heights = [b[3] - b[1] for b in canonical_boxes]
    scale = sum(canonical_heights) / sum(generated_heights)
    generated_axes = [torso_axis_x(cell) for cell, _ in cells]
    canonical_axes = [torso_axis_x(frame) for frame in canonical_frames]
    canonical_mean_axis = sum(canonical_axes) / len(canonical_axes)

    frames = []
    measurements = []
    for index, (cell, raw_box) in enumerate(cells):
        size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
        transformed_cell = cell.resize(size, Image.Resampling.LANCZOS)
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        next_index = (index + 1) % 8
        target_axis = (canonical_axes[index] + canonical_axes[next_index]) / 2
        target_ground = round((canonical_anchors[index]["ground_y_px"] + canonical_anchors[next_index]["ground_y_px"]) / 2)
        x_offset = round(target_axis - generated_axes[index] * scale)
        y_offset = target_ground + 1 - round(raw_box[3] * scale)
        src_left, src_top = max(0, -x_offset), max(0, -y_offset)
        dst_left, dst_top = max(0, x_offset), max(0, y_offset)
        copy_width = min(transformed_cell.width - src_left, TARGET_SIZE - dst_left)
        copy_height = min(transformed_cell.height - src_top, TARGET_SIZE - dst_top)
        if copy_width > 0 and copy_height > 0:
            frame.alpha_composite(
                transformed_cell.crop((src_left, src_top, src_left + copy_width, src_top + copy_height)),
                (dst_left, dst_top),
            )
        anchor_before_correction = bottom_row_anchor(frame)
        anchor_correction = target_ground - anchor_before_correction["ground_y_px"]
        frame = rigid_translate_y(frame, anchor_correction)
        result_box = occupied_bbox(frame)
        if result_box is None:
            raise ValueError("Transformed transition became empty")
        final_anchor = bottom_row_anchor(frame)
        final_axis = torso_axis_x(frame)
        frames.append(frame)
        measurements.append({
            "raw_cell_canvas_px": [cell.width, cell.height],
            "raw_alpha_bbox": list(raw_box),
            "raw_alpha_bbox_size_px": [raw_box[2] - raw_box[0], raw_box[3] - raw_box[1]],
            "transformed_alpha_bbox": list(result_box),
            "transformed_alpha_bbox_size_px": [result_box[2] - result_box[0], result_box[3] - result_box[1]],
            "transformed_bottom_exclusive_px": result_box[3],
            "drift_from_master_mean_alpha_center_x_px": round((result_box[0] + result_box[2]) / 2 - sum((b[0] + b[2]) / 2 for b in canonical_boxes) / 8, 2),
            "drift_from_master_mean_alpha_bottom_px": round(result_box[3] - canonical_boxes[0][3], 2),
            "raw_torso_axis_x_px": round(generated_axes[index], 2),
            "target_torso_axis_x_px": round(target_axis, 2),
            "transformed_torso_axis_x_px": round(final_axis, 2),
            "rigid_torso_translation_px": x_offset,
            "raw_lowest_boot_sole_candidate": bottom_row_anchor(cell),
            "planted_foot_anchor_ground_y_px": target_ground,
            "transformed_lowest_boot_sole_candidate": final_anchor,
            "rigid_ground_translation_px": y_offset,
            "rigid_ground_anchor_correction_px": anchor_correction,
            "rigid_ground_translation_total_px": y_offset + anchor_correction,
        })
    transform = {
        "uniform_scale_factor_applied_to_all_8_cells": round(scale, 6),
        "generated_mean_alpha_height_px": round(sum(generated_heights) / len(generated_heights), 2),
        "canonical_master_mean_alpha_height_px": round(sum(canonical_heights) / len(canonical_heights), 2),
        "canonical_master_mean_torso_axis_x_px": round(canonical_mean_axis, 2),
        "method": "whole fixed-grid cells at one direction-wide scale; rigid per-pose torso-axis and planted-foot translations only; no alpha crop, independent scale or deformation",
    }
    return frames, transform, measurements


def bottom_row_anchor(im: Image.Image):
    """Report the lowest occupied row's horizontal pixels (the boot-sole row)."""
    mask = im.getchannel("A").point(lambda value: 255 if value >= 16 else 0)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("Cannot find a ground anchor in an empty image")
    y = bbox[3] - 1
    pixels = list(mask.crop((0, y, im.width, y + 1)).get_flattened_data())
    occupied = [x for x, value in enumerate(pixels) if value]
    if not occupied:
        raise ValueError("Lowest occupied row has no pixels")
    return {"ground_y_px": y, "x_min_px": min(occupied), "x_max_px": max(occupied),
            "x_mid_px": round((min(occupied) + max(occupied)) / 2, 2)}


def rigid_translate_y(im: Image.Image, dy: int) -> Image.Image:
    """Translate a complete frame vertically without resampling its pixels."""
    if dy == 0:
        return im
    shifted = Image.new("RGBA", im.size, (0, 0, 0, 0))
    src_top = max(0, -dy)
    dst_top = max(0, dy)
    height = min(im.height - src_top, im.height - dst_top)
    if height > 0:
        shifted.alpha_composite(im.crop((0, src_top, im.width, src_top + height)), (0, dst_top))
    return shifted


def transformed_canonical_replacements(cells, canonical_frames):
    """Fit a replacement key sheet with one master scale and rigid key translations."""
    replacement_boxes = [bbox for _, bbox in cells]
    canonical_boxes = [occupied_bbox(frame) for frame in canonical_frames]
    canonical_anchors = [bottom_row_anchor(frame) for frame in canonical_frames]
    replacement_heights = [b[3] - b[1] for b in replacement_boxes]
    canonical_heights = [b[3] - b[1] for b in canonical_boxes]
    scale = sum(canonical_heights) / sum(replacement_heights)
    replacement_axes = [torso_axis_x(cell) for cell, _ in cells]
    canonical_axes = [torso_axis_x(frame) for frame in canonical_frames]
    frames, measurements = [], []
    for index, (cell, raw_box) in enumerate(cells):
        resized = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.Resampling.LANCZOS)
        x_offset = round(canonical_axes[index] - replacement_axes[index] * scale)
        target_ground = canonical_anchors[index]["ground_y_px"]
        y_offset = target_ground + 1 - round(raw_box[3] * scale)
        frame = Image.new("RGBA", (TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
        src_left, src_top = max(0, -x_offset), max(0, -y_offset)
        dst_left, dst_top = max(0, x_offset), max(0, y_offset)
        copy_width = min(resized.width - src_left, TARGET_SIZE - dst_left)
        copy_height = min(resized.height - src_top, TARGET_SIZE - dst_top)
        if copy_width > 0 and copy_height > 0:
            frame.alpha_composite(
                resized.crop((src_left, src_top, src_left + copy_width, src_top + copy_height)),
                (dst_left, dst_top),
            )
        anchor_before_correction = bottom_row_anchor(frame)
        anchor_correction = target_ground - anchor_before_correction["ground_y_px"]
        frame = rigid_translate_y(frame, anchor_correction)
        result_box = occupied_bbox(frame)
        if result_box is None:
            raise ValueError("Canonical replacement became empty")
        raw_anchor = bottom_row_anchor(cell)
        final_anchor = bottom_row_anchor(frame)
        measurements.append({
            "cell_1based": index + 1,
            "raw_cell_canvas_px": [cell.width, cell.height],
            "raw_alpha_bbox": list(raw_box),
            "raw_alpha_bbox_size_px": [raw_box[2] - raw_box[0], raw_box[3] - raw_box[1]],
            "raw_lowest_boot_sole_candidate": raw_anchor,
            "transformed_alpha_bbox": list(result_box),
            "transformed_alpha_bbox_size_px": [result_box[2] - result_box[0], result_box[3] - result_box[1]],
            "source_key_alpha_bbox": list(canonical_boxes[index]),
            "source_key_torso_axis_x_px": round(canonical_axes[index], 2),
            "replacement_raw_torso_axis_x_px": round(replacement_axes[index], 2),
            "rigid_torso_translation_px": x_offset,
            "source_key_ground_y_exclusive_px": canonical_boxes[index][3],
            "source_key_support_foot_ground_y_px": target_ground,
            "rigid_ground_translation_px": y_offset,
            "rigid_ground_anchor_correction_px": anchor_correction,
            "rigid_ground_translation_total_px": y_offset + anchor_correction,
            "transformed_lowest_boot_sole_candidate": final_anchor,
            "source_pixels_changed": False,
        })
        frames.append(frame)
    transform = {
        "uniform_scale_factor_applied_to_all_8_replacement_keys": round(scale, 6),
        "replacement_mean_alpha_height_px": round(sum(replacement_heights) / len(replacement_heights), 2),
        "canonical_master_mean_alpha_height_px": round(sum(canonical_heights) / len(canonical_heights), 2),
        "method": "full fixed-grid cells at one common scale; rigid per-key torso-axis and lowest-boot-sole-ground translations only; no alpha-crop normalization, per-key scaling, warping or mirroring",
    }
    return frames, transform, measurements


def build_canonical_candidate(direction="south", config=None):
    """Write a review-only 16-phase candidate using corrected canonical keys."""
    config = config or {
        "candidate_version": "v2",
        "key_image": "walk_south-canonical-correction-imagegen-v4.png",
        "transition_image": "walk_south-corrected-transitions-imagegen-v2.png",
        "key_generation_id": "exec-249b4594-eedf-43d5-962e-5447081377b6.png",
        "transition_generation_id": "exec-06e3c115-4140-43f5-8253-8971b19b2a7e.png",
        "key_prompt": "prompts/walk_south-canonical-correction-v4.txt",
        "transition_prompt": "prompts/walk_south-corrected-transitions-v2.txt",
        "key_references": [
            {"path": "assets/source/cat-worker-v1/locomotion/idle_south.png", "role": "Identity, outfit, south-facing camera, pixel-art style and size reference."},
            {"path": "generated/references/south-leg-role-diagram-v1.png", "role": "Eight-phase screen-left/screen-right leg-role guide only; not a character/style reference."},
        ],
        "transition_reference_role": "Image 1: corrected south-facing eight-key v4 candidate, sole character/style/scale/phase-role reference; transitions generated specifically against these keys.",
        "corrected_roles": ["screen-left contact", "screen-left weight-down", "screen-left support with screen-right passing", "screen-left support with screen-right knee-up", "screen-right contact", "screen-right weight-down", "screen-right support with screen-left passing", "screen-right support with screen-left knee-up"],
        "review_limitations": ["South original frames 1 and 5 visibly repeat the same apparent picture-left contact; v4 was generated with explicit screen-side support ownership for contact, passing and knee-up pairs. Root review of every neighboring key/transition pair remains required."],
    }
    candidate_version = config.get("candidate_version", "v1")
    source_path = ROOT / SOURCE_STRIPS[direction]
    source = Image.open(source_path).convert("RGBA")
    canonical = [source.crop((i * TARGET_SIZE, 0, (i + 1) * TARGET_SIZE, TARGET_SIZE)) for i in range(8)]
    raw_path = STAGE / "generated" / config["key_image"]
    raw_sheet = Image.open(raw_path).convert("RGBA")
    cells = split_generated_sheet(raw_sheet)
    replacements, transform, measurements = transformed_canonical_replacements(cells, canonical)

    transition_raw_path = STAGE / "generated" / config["transition_image"]
    transition_sheet = Image.open(transition_raw_path).convert("RGBA")
    transition_cells = split_generated_sheet(transition_sheet)
    corrected_transitions, transition_transform, transition_measurements = transformed_transition_cells(transition_cells, replacements)

    replacement_dir = STAGE / "canonical-replacements"
    replacement_dir.mkdir(parents=True, exist_ok=True)
    replacement_strip = Image.new("RGBA", (8 * TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
    transition_strip = Image.new("RGBA", (8 * TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
    proposed_strip = Image.new("RGBA", (16 * TARGET_SIZE, TARGET_SIZE), (0, 0, 0, 0))
    for i in range(8):
        replacement_strip.alpha_composite(replacements[i], (i * TARGET_SIZE, 0))
        transition_strip.alpha_composite(corrected_transitions[i], (i * TARGET_SIZE, 0))
        proposed_strip.alpha_composite(replacements[i], (2 * i * TARGET_SIZE, 0))
        proposed_strip.alpha_composite(corrected_transitions[i], ((2 * i + 1) * TARGET_SIZE, 0))
    replacement_path = replacement_dir / f"walk_{direction}-corrected-canonical-8phase-{candidate_version}.png"
    transition_path = replacement_dir / f"walk_{direction}-corrected-transitions-8phase-{candidate_version}.png"
    proposed_path = replacement_dir / f"walk_{direction}-corrected-canonical-16phase-candidate-{candidate_version}.png"
    replacement_strip.save(replacement_path, optimize=True)
    transition_strip.save(transition_path, optimize=True)
    proposed_strip.save(proposed_path, optimize=True)

    candidate_dir = OUTPUT / "canonical-correction-candidate"
    candidate_dir.mkdir(parents=True, exist_ok=True)
    runtime_frames = [proposed_strip.crop((i * TARGET_SIZE, 0, (i + 1) * TARGET_SIZE, TARGET_SIZE)).resize((256, 256), Image.Resampling.LANCZOS) for i in range(16)]
    runtime_strip = Image.new("RGBA", (16 * 256, 256), (0, 0, 0, 0))
    for i, frame in enumerate(runtime_frames):
        runtime_strip.alpha_composite(frame, (i * 256, 0))
    runtime_path = candidate_dir / f"walk_{direction}-corrected-canonical-16phase-256-candidate-{candidate_version}.png"
    runtime_strip.save(runtime_path, optimize=True)
    detail = Image.new("RGBA", (4 * 320, 4 * 340), (54, 58, 56, 255))
    draw = ImageDraw.Draw(detail)
    for i, frame in enumerate(runtime_frames):
        x, y = (i % 4) * 320, (i // 4) * 340
        draw.text((x + 4, y + 3), f"{i + 1:02d} {'K' if i % 2 == 0 else 'T'}", fill=(242, 242, 234, 255))
        detail.alpha_composite(frame.resize((256, 256), Image.Resampling.NEAREST), (x + 32, y + 28))
    contact_path = candidate_dir / f"walk_{direction}-corrected-canonical-16phase-contact-{candidate_version}.png"
    detail.convert("RGB").save(contact_path)
    loop_path = candidate_dir / f"walk_{direction}-corrected-canonical-16phase-loop-{candidate_version}.gif"
    runtime_frames[0].save(loop_path,
                           save_all=True, append_images=runtime_frames[1:], duration=90,
                           loop=0, disposal=2, optimize=False)

    return {
        "status": "candidate_staged_for_parent_visual_review; not runtime_registered",
        "candidate_version": candidate_version,
        "direction": direction,
        "approved_source_master": SOURCE_STRIPS[direction],
        "approved_source_sha256": file_hash(source_path),
        "source_canonical_pixels_changed": False,
        "imagegen_output_original": str(GENERATED_ROOT / config["key_generation_id"]),
        "imagegen_output_staged": raw_path.relative_to(ROOT).as_posix(),
        "imagegen_sha256": file_hash(raw_path),
        "imagegen_dimensions": list(raw_sheet.size),
        "exact_prompt_path": config["key_prompt"],
        "reference_images": config["key_references"],
        "selected_cell_mapping": [
            {"cell_1based": i + 1, "row_0based": i // 4, "column_0based": i % 4,
             "canonical_phase": PHASES[i], "corrected_role": config["corrected_roles"][i],
             "raw_cell_sha256": sha256(cells[i][0].tobytes()).hexdigest(),
             "normalized_frame_sha256": sha256(replacements[i].tobytes()).hexdigest()}
            for i in range(8)
        ],
        "uniform_replacement_transform": transform,
        "per_key_anchor_and_size_measurements": measurements,
        "corrected_canonical_strip": replacement_path.relative_to(ROOT).as_posix(),
        "corrected_canonical_strip_sha256": file_hash(replacement_path),
        "corrected_transition_strip": transition_path.relative_to(ROOT).as_posix(),
        "corrected_transition_strip_sha256": file_hash(transition_path),
        "proposed_16phase_strip": proposed_path.relative_to(ROOT).as_posix(),
        "proposed_16phase_strip_sha256": file_hash(proposed_path),
        "proposed_16phase_runtime_preview": runtime_path.relative_to(ROOT).as_posix(),
        "proposed_16phase_contact_preview": contact_path.relative_to(ROOT).as_posix(),
        "proposed_16phase_loop_preview": loop_path.relative_to(ROOT).as_posix(),
        "transition_imagegen_output_original": str(GENERATED_ROOT / config["transition_generation_id"]),
        "transition_imagegen_output_staged": transition_raw_path.relative_to(ROOT).as_posix(),
        "transition_imagegen_sha256": file_hash(transition_raw_path),
        "transition_imagegen_dimensions": list(transition_sheet.size),
        "transition_exact_prompt_path": config["transition_prompt"],
        "transition_reference_role": config["transition_reference_role"],
        "selected_transition_cells": [
            {"cell_1based": i + 1, "row_0based": i // 4, "column_0based": i % 4,
             "transition": f"{PHASES[i]} -> {PHASES[(i + 1) % 8]}",
             "raw_cell_sha256": sha256(transition_cells[i][0].tobytes()).hexdigest(),
             "normalized_frame_sha256": sha256(corrected_transitions[i].tobytes()).hexdigest()}
            for i in range(8)
        ],
        "uniform_transition_transform": transition_transform,
        "per_transition_anchor_and_size_measurements": transition_measurements,
        "review_limitations": [
            *config["review_limitations"],
            "Generated corrected key poses have not yet been accepted as final by the root reviewer.",
            "The generated transition sheet references the corrected key candidate; per-frame neighbor interpolation and foot ownership still require root visual acceptance.",
        ],
    }


def write_corrected_key_audit_spec(direction_corrected: str, corrected_key_strip: str):
    animations, directions = {}, {}
    for direction in DIRECTIONS:
        name = f"walk_{direction}"
        path = (corrected_key_strip if direction == direction_corrected else SOURCE_STRIPS[direction])
        animations[name] = {"path": path, "frame_width": 512, "frame_height": 512,
                            "frame_count": 8, "loop": True, "role": "gait"}
        idle_name = f"idle_{direction}"
        idle_path = ("assets/generated/characters/cat-worker/idle.png"
                     if direction == "east"
                     else f"assets/generated/characters/cat-worker/idle_{direction}.png")
        animations[idle_name] = {"path": idle_path, "frame_width": 256, "frame_height": 256,
                                 "frame_count": 2, "loop": True, "role": "directional_idle", "fps": 0.65}
        directions[direction] = {"walk_animation": name, "idle_animation": idle_name, "mirror_x": False}
    spec = {
        "version": 1, "character": f"cat-worker-{direction_corrected}-corrected-keys", "status": "staged_art_review_only",
        "animations": animations, "directions": directions,
        "gait": {"pose_order": PHASES, "pixels_per_frame": 6.5, "base_speed": 72,
                 "speed_multipliers": [1.0] * 8, "acceleration_multipliers": [1.0] * 8},
        "audit": {"alpha_threshold": 16, "edge_margin": 2, "detached_component_ratio": 0.003,
                  "baseline_tolerance": 4, "center_tolerance": 14},
        "audit_note": f"Eight-phase corrected {direction_corrected}-key review candidate. This does not replace source/runtime strips; the corrected candidate remains subject to root visual acceptance.",
    }
    path = STAGE / f"cat-worker-{direction_corrected}-corrected-key-audit-spec.json"
    path.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")


def write_corrected_transition_audit_spec(direction_corrected: str, corrected_transition_strip: str):
    animations, directions = {}, {}
    poses = [f"transition_{PHASES[i]}_to_{PHASES[(i + 1) % 8]}" for i in range(8)]
    for direction in DIRECTIONS:
        name = f"walk_{direction}_transitions"
        path = (corrected_transition_strip if direction == direction_corrected
                else f"assets/source/animation-overhaul-luna-v1/cat-worker/transitions/walk_{direction}-transitions-8frame-audit.png")
        animations[name] = {"path": path, "frame_width": 512, "frame_height": 512,
                            "frame_count": 8, "loop": True, "role": "gait"}
        idle_name = f"idle_{direction}"
        idle_path = ("assets/generated/characters/cat-worker/idle.png"
                     if direction == "east"
                     else f"assets/generated/characters/cat-worker/idle_{direction}.png")
        animations[idle_name] = {"path": idle_path, "frame_width": 256, "frame_height": 256,
                                 "frame_count": 2, "loop": True, "role": "directional_idle", "fps": 0.65}
        directions[direction] = {"walk_animation": name, "idle_animation": idle_name, "mirror_x": False}
    spec = {
        "version": 1, "character": f"cat-worker-{direction_corrected}-corrected-transitions", "status": "staged_art_review_only",
        "animations": animations, "directions": directions,
        "gait": {"pose_order": poses, "pixels_per_frame": 13, "base_speed": 72,
                 "speed_multipliers": [1.0] * 8, "acceleration_multipliers": [1.0] * 8},
        "audit": {"alpha_threshold": 16, "edge_margin": 2, "detached_component_ratio": 0.003,
                  "baseline_tolerance": 4, "center_tolerance": 14},
        "audit_note": f"The {direction_corrected} transition strip was regenerated against the corrected {direction_corrected} canonical candidate. Other transition strips remain the original direction-specific generated candidates. This is a strict art audit only; parent review still owns foot-role and interpolation acceptance.",
    }
    (STAGE / f"cat-worker-{direction_corrected}-corrected-transition-audit-spec.json").write_text(
        json.dumps(spec, indent=2) + "\n", encoding="utf-8")


def contact_sheet(frames_by_direction, path: Path, cell_size: int = 128):
    label_w = 92
    label_h = 18
    bg = (54, 58, 56, 255)
    sheet = Image.new("RGBA", (label_w + 16 * cell_size, 8 * (cell_size + label_h)), bg)
    draw = ImageDraw.Draw(sheet)
    for row, direction in enumerate(DIRECTIONS):
        y = row * (cell_size + label_h)
        draw.text((5, y + label_h // 2 - 4), direction, fill=(245, 245, 238, 255))
        for i, frame in enumerate(frames_by_direction[direction]):
            x = label_w + i * cell_size
            tile = frame.resize((cell_size, cell_size), Image.Resampling.NEAREST)
            sheet.alpha_composite(tile, (x, y + label_h))
            draw.text((x + 2, y + 1), f"{i:02d}{'K' if i % 2 == 0 else 'T'}", fill=(230, 230, 210, 255))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(path, quality=95)


def write_audit_spec():
    pose_order = []
    for i, phase in enumerate(PHASES):
        pose_order.append(phase)
        next_phase = PHASES[(i + 1) % len(PHASES)]
        pose_order.append(f"transition_{phase}_to_{next_phase}")
    animations = {}
    directions = {}
    for direction in DIRECTIONS:
        name = f"walk_{direction}"
        path = STAGE / "strips" / f"walk_{direction}-16phase-v1.png"
        animations[name] = {"path": path.relative_to(ROOT).as_posix(), "frame_width": 512,
                            "frame_height": 512, "frame_count": 16, "loop": True, "role": "gait"}
        idle_name = f"idle_{direction}"
        idle_path = (ROOT / "assets/generated/characters/cat-worker/idle.png"
                     if direction == "east"
                     else ROOT / f"assets/generated/characters/cat-worker/idle_{direction}.png")
        animations[idle_name] = {"path": idle_path.relative_to(ROOT).as_posix(), "frame_width": 256,
                                 "frame_height": 256, "frame_count": 2, "loop": True,
                                 "role": "directional_idle", "fps": 0.65}
        directions[direction] = {"walk_animation": name, "idle_animation": idle_name, "mirror_x": False}
    spec = {
        "version": 1,
        "character": "cat-worker",
        "status": "staged_art_review_only",
        "animations": animations,
        "directions": directions,
        "gait": {"pose_order": pose_order, "pixels_per_frame": 6.5, "base_speed": 72,
                 "speed_multipliers": [1.0] * 16, "acceleration_multipliers": [1.0] * 16},
        "audit": {"alpha_threshold": 16, "edge_margin": 2, "detached_component_ratio": 0.003,
                  "baseline_tolerance": 4, "center_tolerance": 14},
        "audit_note": "Luna staging-only 16-drawing art review. Runtime timing and subdivision integration remain owned by the root agent.",
    }
    (STAGE / "cat-worker-16phase-art-audit-spec.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")


def write_transition_audit_spec(transitions_by_direction):
    """Stage the eight generated in-betweens for the auditor's 8-pose gate."""
    poses = [f"transition_{PHASES[i]}_to_{PHASES[(i + 1) % 8]}" for i in range(8)]
    animations = {}
    directions = {}
    for direction in DIRECTIONS:
        name = f"walk_{direction}_transitions"
        strip = Image.new("RGBA", (8 * 512, 512), (0, 0, 0, 0))
        for i, frame in enumerate(transitions_by_direction[direction]):
            strip.alpha_composite(frame, (i * 512, 0))
        strip_path = STAGE / "transitions" / f"walk_{direction}-transitions-8frame-audit.png"
        strip_path.parent.mkdir(parents=True, exist_ok=True)
        strip.save(strip_path, optimize=True)
        animations[name] = {"path": strip_path.relative_to(ROOT).as_posix(), "frame_width": 512,
                            "frame_height": 512, "frame_count": 8, "loop": True, "role": "gait"}
        idle_name = f"idle_{direction}"
        idle_path = (ROOT / "assets/generated/characters/cat-worker/idle.png"
                     if direction == "east"
                     else ROOT / f"assets/generated/characters/cat-worker/idle_{direction}.png")
        animations[idle_name] = {"path": idle_path.relative_to(ROOT).as_posix(), "frame_width": 256,
                                 "frame_height": 256, "frame_count": 2, "loop": True,
                                 "role": "directional_idle", "fps": 0.65}
        directions[direction] = {"walk_animation": name, "idle_animation": idle_name, "mirror_x": False}
    spec = {
        "version": 1,
        "character": "cat-worker",
        "status": "staged_transition_art_review_only",
        "animations": animations,
        "directions": directions,
        "gait": {"pose_order": poses, "pixels_per_frame": 13, "base_speed": 72,
                 "speed_multipliers": [1.0] * 8, "acceleration_multipliers": [1.0] * 8},
        "audit": {"alpha_threshold": 16, "edge_margin": 2, "detached_component_ratio": 0.003,
                  "baseline_tolerance": 4, "center_tolerance": 14},
        "audit_note": "This 8-pose strip contains only newly generated midpoint drawings so the bundled auditor can check their bounds, duplicates and loop seam. It is not the runtime strip; root owns 16-drawing timing integration.",
    }
    (STAGE / "cat-worker-transition-art-audit-spec.json").write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")


def build():
    (STAGE / "generated").mkdir(parents=True, exist_ok=True)
    (STAGE / "prompts").mkdir(parents=True, exist_ok=True)
    (STAGE / "strips").mkdir(parents=True, exist_ok=True)
    (OUTPUT / "runtime").mkdir(parents=True, exist_ok=True)
    (OUTPUT / "previews").mkdir(parents=True, exist_ok=True)

    manifest = {
        "version": 1,
        "character": "cat-worker",
        "stage": "assets/source/animation-overhaul-luna-v1/cat-worker",
        "output": "output/animation-overhaul/luna-cat",
        "generator": "built-in image_gen",
        "reference_role": "Primary transitions reference each approved direction-matched source walk strip without editing it. The south canonical replacement uses the approved south idle for identity/style only, and its transitions use that corrected key set. East/west corrective generations are retained as rejected attempts with their reference roles.",
        "reference_sha256": file_hash(ROOT / "references/characters/cat-worker/radio-cat-reference.png"),
        "directions": {},
        "pose_mapping": [],
        "rejected_generations": [],
        "runtime_integration_note": "The 16 drawings subdivide each original phase interval. Keep each direction's eight canonical frames at indices 0,2,...,14; timing subdivision and shared runtime/config changes belong to the root integrator.",
    }
    all_frames = {}
    transitions_by_direction = {}

    for direction in DIRECTIONS:
        source_path = ROOT / SOURCE_STRIPS[direction]
        source = Image.open(source_path).convert("RGBA")
        if source.size != (4096, 512):
            raise ValueError(f"Unexpected immutable master dimensions {source_path}: {source.size}")
        canonical = [source.crop((i * 512, 0, (i + 1) * 512, 512)) for i in range(8)]
        source_boxes = [occupied_bbox(frame) for frame in canonical]
        source_heights = [box[3] - box[1] for box in source_boxes]
        source_widths = [box[2] - box[0] for box in source_boxes]

        generated_source = GENERATED_ROOT / GENERATIONS[direction]
        staged_generated = STAGE / "generated" / f"walk_{direction}-transitions-imagegen-v1.png"
        shutil.copy2(generated_source, staged_generated)
        generated = Image.open(staged_generated).convert("RGBA")
        generated_cells = split_generated_sheet(generated)
        transitions, rigid_transform, transition_measurements = transformed_transition_cells(generated_cells, canonical)
        generated_heights = [box[3] - box[1] for _, box in generated_cells]
        transitions_by_direction[direction] = transitions

        out_frames = []
        for i in range(8):
            out_frames.extend([canonical[i], transitions[i]])
        source_strip = Image.new("RGBA", (16 * 512, 512), (0, 0, 0, 0))
        for i, frame in enumerate(out_frames):
            source_strip.alpha_composite(frame, (i * 512, 0))
        staged_strip = STAGE / "strips" / f"walk_{direction}-16phase-v1.png"
        source_strip.save(staged_strip, optimize=True)

        runtime_frames = [frame.resize((256, 256), Image.Resampling.LANCZOS) for frame in out_frames]
        runtime_strip = Image.new("RGBA", (16 * 256, 256), (0, 0, 0, 0))
        for i, frame in enumerate(runtime_frames):
            runtime_strip.alpha_composite(frame, (i * 256, 0))
        runtime_path = OUTPUT / "runtime" / f"walk_{direction}-16phase-256-v1.png"
        runtime_strip.save(runtime_path, optimize=True)
        all_frames[direction] = runtime_frames

        # Per-direction detail contact sheet and loop preview at twice the old
        # per-phase rate, preserving the old eight-phase cycle duration.
        detail = Image.new("RGBA", (8 * 160, 2 * 180), (54, 58, 56, 255))
        draw = ImageDraw.Draw(detail)
        for i, frame in enumerate(runtime_frames):
            x, y = (i % 8) * 160, (i // 8) * 180
            if i < 8:
                pass
            draw.text((x + 3, y + 3), f"{i:02d} {'K' if i % 2 == 0 else 'T'}", fill=(242, 242, 234, 255))
            detail.alpha_composite(frame.resize((160, 160), Image.Resampling.NEAREST), (x, y + 20))
        detail.convert("RGB").save(OUTPUT / "previews" / f"walk_{direction}-16phase-contact.png")
        runtime_frames[0].save(OUTPUT / "previews" / f"walk_{direction}-16phase-loop.gif",
                               save_all=True, append_images=runtime_frames[1:], duration=90,
                               loop=0, disposal=2, transparency=0, optimize=False)

        existing_runtime = Image.open(ROOT / RUNTIME_STRIPS[direction]).convert("RGBA")
        current_canonical_match = []
        for i in range(8):
            existing_frame = existing_runtime.crop((i * 256, 0, (i + 1) * 256, 256))
            staged_frame = runtime_frames[2 * i]
            current_canonical_match.append(existing_frame.tobytes() == staged_frame.tobytes())

        manifest["directions"][direction] = {
            "approved_source": SOURCE_STRIPS[direction],
            "approved_source_sha256": file_hash(source_path),
            "approved_source_dimensions": list(source.size),
            "existing_runtime_reference": RUNTIME_STRIPS[direction],
            "existing_runtime_sha256": file_hash(ROOT / RUNTIME_STRIPS[direction]),
            "reference_role": f"Image 1: direction-matched approved source strip for {direction}; reference only, not edited.",
            "imagegen_prompt": f"prompts/walk_{direction}-transitions.txt",
            "imagegen_output_original": str(generated_source),
            "imagegen_output_staged": staged_generated.relative_to(ROOT).as_posix(),
            "imagegen_sha256": file_hash(staged_generated),
            "imagegen_dimensions": list(generated.size),
            "selected_cells": [
                {"cell": i + 1, "row": i // 4, "column": i % 4,
                 "transition": f"{PHASES[i]} -> {PHASES[(i + 1) % 8]}",
                 "raw_cell_sha256": sha256(generated_cells[i][0].tobytes()).hexdigest(),
                 "normalized_frame_sha256": sha256(transitions[i].tobytes()).hexdigest()}
                for i in range(8)
            ],
            "normalization": {
                "canonical_master_alpha_bbox_sizes_px": [[b[2] - b[0], b[3] - b[1]] for b in source_boxes],
                "canonical_master_alpha_bbox_heights_px": source_heights,
                "canonical_master_alpha_bbox_widths_px": source_widths,
                "canonical_master_source_size_drift": {
                    "height_min_max_px": [min(source_heights), max(source_heights)],
                    "height_range_px": max(source_heights) - min(source_heights),
                    "width_min_max_px": [min(source_widths), max(source_widths)],
                    "width_range_px": max(source_widths) - min(source_widths),
                    "note": "Source pose bounds are reported as-authored; no independent per-pose normalization was applied.",
                },
                "rigid_direction_transform": rigid_transform,
                "per_transition_size_and_anchor_drift": transition_measurements,
                "normalized_frame_px": [512, 512],
                "resampling": "Pillow LANCZOS on each full fixed-grid cell; the same single scale and translation were applied to all eight cells in this direction",
            },
            "source_strip_16phase": staged_strip.relative_to(ROOT).as_posix(),
            "source_strip_sha256": file_hash(staged_strip),
            "transition_only_audit_strip": (STAGE / "transitions" / f"walk_{direction}-transitions-8frame-audit.png").relative_to(ROOT).as_posix(),
            "runtime_preview_strip_16phase": runtime_path.relative_to(ROOT).as_posix(),
            "runtime_preview_sha256": file_hash(runtime_path),
            "canonical_runtime_pixel_match_by_phase": current_canonical_match,
            "runtime_preview_frame_px": [256, 256],
            "frame_count": 16,
            "mirror_x": False,
            "canonical_role_audit": CANONICAL_ROLE_AUDIT[direction],
            "preview_fps": 72 / 6.5,
            "preview_cycle_seconds": 16 / (72 / 6.5),
        }

        for i, phase in enumerate(PHASES):
            if direction == DIRECTIONS[0]:
                manifest["pose_mapping"].append({
                    "original_phase_index_1based": i + 1,
                    "canonical_phase": phase,
                    "16phase_index_1based": 2 * i + 1,
                    "transition_index_1based": 2 * i + 2,
                    "transition_semantics": f"between {phase} and {PHASES[(i + 1) % 8]}",
                    "selected_generated_cell_1based": i + 1,
                })

        prompt_path = STAGE / "prompts" / f"walk_{direction}-transitions.txt"
        prompt_path.write_text(PROMPTS[direction] + "\n", encoding="utf-8")

    # A south-only alternate is staged because the original frontal contact pair
    # visibly repeats one foot role. The primary strips above remain source-exact.
    south_candidate = build_canonical_candidate()
    manifest["canonical_replacement_candidates"] = [south_candidate]
    manifest["superseded_canonical_candidates"] = [{
        "direction": "south",
        "canonical_strip": "assets/source/animation-overhaul-luna-v1/cat-worker/canonical-replacements/walk_south-corrected-canonical-8phase-v1.png",
        "transitions_strip": "assets/source/animation-overhaul-luna-v1/cat-worker/canonical-replacements/walk_south-corrected-transitions-8phase-v1.png",
        "16phase_strip": "assets/source/animation-overhaul-luna-v1/cat-worker/canonical-replacements/walk_south-corrected-canonical-16phase-candidate-v1.png",
        "contact_preview": "output/animation-overhaul/luna-cat/canonical-correction-candidate/walk_south-corrected-canonical-16phase-contact-512-v1.png",
        "reason": "Superseded after detailed comparison: contacts 1/5 visibly alternated, but passing 3/7 and knee-up 4/8 did not read as sufficiently distinct opposite-side roles. Retained for provenance only; v2 uses a new eight-phase role guide and matching transition generation.",
    }]
    write_corrected_key_audit_spec("south", south_candidate["corrected_canonical_strip"])
    write_corrected_transition_audit_spec("south", south_candidate["corrected_transition_strip"])
    rejected_contact = STAGE / "generated/rejected-canonical/south-right-contact-imagegen-v1.png"
    if rejected_contact.exists():
        rejected_image = Image.open(rejected_contact)
        manifest["rejected_generations"].append({
            "direction": "south",
            "purpose": "single opposite-contact canonical pose",
            "original_path": str(GENERATED_ROOT / "exec-526e8929-8975-4278-b466-818056a90106.png"),
            "staged_path": rejected_contact.relative_to(ROOT).as_posix(),
            "sha256": file_hash(rejected_contact),
            "dimensions": list(rejected_image.size),
            "prompt_path": "prompts/south-right-contact-correction-v1.txt",
            "reference_role": "Image 1: approved south source phase 1 crop; style/identity only, no mirrored pose source.",
            "reason": "Pose showed the opposite picture-side boot forward, but this standalone drawing was not used: it would require a per-frame size fit relative to an eight-key master. The unified eight-key candidate is the only corrected-base candidate staged into a 16-phase preview.",
        })

    rejected_canonical_attempts = [
        {
            "direction": "east", "purpose": "eight-key canonical correction, first attempt",
            "generation_id": "exec-7dc69817-5a87-459b-b3b3-ae5b617d487d.png",
            "staged_path": "generated/walk_east-canonical-correction-imagegen-v1.png",
            "prompt_path": "prompts/walk_east-canonical-correction-v1.txt",
            "reference_images": [{"path": "assets/source/cat-worker-v1/locomotion/idle.png", "role": "East-facing identity, outfit and pixel-style reference only."}],
            "reason": "Phases 1 and 5 retain the same visible screen-right forward boot; no accepted correction.",
        },
        {
            "direction": "east", "purpose": "eight-key canonical correction, explicit role prompt",
            "generation_id": "exec-183ef8ec-2b66-40bd-83f4-7188682fbc8f.png",
            "staged_path": "generated/rejected-canonical/east-canonical-v2-rejected.png",
            "prompt_path": "prompts/walk_east-canonical-correction-v2.txt",
            "reference_images": [
                {"path": "assets/source/cat-worker-v1/locomotion/idle.png", "role": "East-facing identity, outfit, style and direction reference."},
                {"path": "assets/source/cat-worker-v1/locomotion/walk.png", "role": "Original pose order, camera and stride context; its repeated contact-foot role is explicitly not to be copied."},
            ],
            "reason": "Phases 1 and 5 still show the same near-side boot forward; background is an opaque generated checkerboard, so the sheet is rejected.",
        },
        {
            "direction": "east", "purpose": "two-contact canonical correction, first attempt",
            "generation_id": "exec-3b12ca6e-5b5d-4bcb-a156-f29eebed1298.png",
            "staged_path": "generated/rejected-canonical/east-contact-pair-v1-rejected.png",
            "prompt_path": "prompts/walk_east-contact-pair-correction-v1.txt",
            "reference_images": [{"path": "assets/source/cat-worker-v1/locomotion/idle.png", "role": "East-facing identity/style reference only."}],
            "reason": "Both panels repeat the same visible leg arrangement and forward boot; no opposite contact pose was achieved.",
        },
        {
            "direction": "east", "purpose": "single phase-5 contact replacement",
            "generation_id": "exec-908f653e-b2b1-41ba-8ea2-77e39b28fe41.png",
            "staged_path": "generated/rejected-canonical/east-phase5-contact-v1-rejected.png",
            "prompt_path": "prompts/walk_east-phase5-contact-correction-v1.txt",
            "reference_images": [
                {"path": "assets/source/cat-worker-v1/locomotion/idle.png", "role": "East-facing identity/style reference."},
                {"path": "generated/references/east-v2-phase1-contact-reference.png", "role": "Unaltered crop of phase 1 from the rejected east canonical v2 sheet, used as the visual key to replace with opposite support."},
            ],
            "reason": "The output retains the reference's near-side forward boot instead of assigning phase-5 support to the opposite leg; opaque checkerboard background also makes it unusable.",
        },
        {
            "direction": "east", "purpose": "two-contact canonical correction with leg-role diagram",
            "generation_id": "exec-481e1076-ce0f-42c9-bc68-ee2b39611532.png",
            "staged_path": "generated/rejected-canonical/east-contact-pair-v2-rejected.png",
            "prompt_path": "prompts/walk_east-contact-pair-correction-v2.txt",
            "reference_images": [
                {"path": "assets/source/cat-worker-v1/locomotion/idle.png", "role": "Sole character identity/style reference."},
                {"path": "generated/references/east-contact-role-diagram.png", "role": "Leg ownership and overlap only: red foreground-near leg versus blue background-far leg; not a character/style reference."},
            ],
            "reason": "The two contacts still duplicate the same forward near-side support despite the role diagram; no accepted correction.",
        },
        {
            "direction": "west", "purpose": "eight-key canonical correction",
            "generation_id": "exec-162f9a4a-7813-4a00-a1a9-e75078be618e.png",
            "staged_path": "generated/rejected-canonical/west-canonical-v1-rejected.png",
            "prompt_path": "prompts/walk_west-canonical-correction-v1.txt",
            "reference_images": [
                {"path": "assets/source/cat-worker-v1/locomotion/idle_west.png", "role": "West-facing identity, outfit, style and asymmetric-side reference."},
                {"path": "assets/source/cat-worker-v1/locomotion/walk_west.png", "role": "Original phase order and stride context; its repeated contact-foot role is explicitly not to be copied."},
            ],
            "reason": "Phases 1 and 5 retain the same visible screen-left forward boot. The generated view also drifts toward three-quarter front and has an opaque checkerboard; no accepted correction.",
        },
    ]
    for attempt in rejected_canonical_attempts:
        staged = STAGE / attempt["staged_path"]
        if not staged.exists():
            raise FileNotFoundError(f"Missing staged rejected generation: {staged}")
        image = Image.open(staged)
        manifest["rejected_generations"].append({
            **attempt,
            "original_path": str(GENERATED_ROOT / attempt["generation_id"]),
            "sha256": file_hash(staged),
            "dimensions": list(image.size),
            "alpha_extrema": list(image.convert("RGBA").getchannel("A").getextrema()),
            "review_status": "rejected_after_visual_inspection",
        })

    # Save the exact prompt set and all frame mappings as durable provenance.
    (STAGE / "prompt-set.json").write_text(json.dumps({
        "generator": "built-in image_gen",
        "transparent_background": True,
        "directions": {d: {"prompt_path": f"prompts/walk_{d}-transitions.txt", "exact_prompt": PROMPTS[d],
                           "reference_role": f"Image 1: approved cat-worker {d} 8-phase source strip, identity/style/angle reference only."}
                       for d in DIRECTIONS},
        "canonical_correction_candidates": {
            "south": {
                "candidate_version": "v2",
                "prompt_path": "prompts/walk_south-canonical-correction-v4.txt",
                "exact_prompt": (STAGE / "prompts/walk_south-canonical-correction-v4.txt").read_text(encoding="utf-8").strip(),
                "reference_images": [
                    {"path": "assets/source/cat-worker-v1/locomotion/idle_south.png", "role": "Identity, outfit, south-facing camera, pixel-art style, palette and scale."},
                    {"path": "generated/references/south-leg-role-diagram-v1.png", "role": "Leg ownership and phase motion only; red marks screen-left and blue marks screen-right."},
                ],
                "transition_prompt_path": "prompts/walk_south-corrected-transitions-v2.txt",
                "transition_exact_prompt": (STAGE / "prompts/walk_south-corrected-transitions-v2.txt").read_text(encoding="utf-8").strip(),
                "transition_reference_role": "Image 1: corrected south-facing eight-key v4 candidate, sole character/style/scale/phase-role reference.",
            }
        },
        "canonical_correction_attempts": [
            {
                "direction": attempt["direction"],
                "purpose": attempt["purpose"],
                "prompt_path": attempt["prompt_path"],
                "exact_prompt": (STAGE / attempt["prompt_path"]).read_text(encoding="utf-8").strip(),
                "reference_images": attempt["reference_images"],
                "generation_id": attempt["generation_id"],
                "staged_path": attempt["staged_path"],
                "review_status": "rejected_after_visual_inspection",
                "reason": attempt["reason"],
            }
            for attempt in rejected_canonical_attempts
        ],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # The alternate north candidate was inspected but not selected because its
    # 1774x887 sheet has half-pixel cell boundaries and weaker leg-role clarity.
    alternate_north = GENERATED_ROOT / "exec-827cee28-5b10-472c-b2c0-8922c2241172.png"
    if alternate_north.exists():
        manifest["rejected_generations"].append({
            "direction": "north",
            "original_path": str(alternate_north),
            "sha256": file_hash(alternate_north),
            "dimensions": list(Image.open(alternate_north).size),
            "reason": "Inspected alternate generation; rejected in favor of the 1536x1024 exact 384x512 panel layout and clearer alternating support/swing leg separation.",
        })

    contact_sheet(all_frames, OUTPUT / "previews" / "cat-worker-16phase-all-directions-contact.jpg")
    manifest["previews"] = {
        "all_directions_contact": "output/animation-overhaul/luna-cat/previews/cat-worker-16phase-all-directions-contact.jpg",
        "per_direction_contact_pattern": "output/animation-overhaul/luna-cat/previews/walk_{direction}-16phase-contact.png",
        "per_direction_loop_pattern": "output/animation-overhaul/luna-cat/previews/walk_{direction}-16phase-loop.gif",
    }
    write_audit_spec()
    write_transition_audit_spec(transitions_by_direction)
    (STAGE / "provenance-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Staged 8 cat-worker directions: source strips at {STAGE / 'strips'}; runtime preview strips at {OUTPUT / 'runtime'}")


if __name__ == "__main__":
    build()
