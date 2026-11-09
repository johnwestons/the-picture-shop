"""Pack dressing candidates for review only; never publish runtime actor assets.

Only crop, uniformly resample and register original generated RGBA pixels.
The helmet lift reaches above its nominal second-row cell, so that sheet has
an explicit 495px row boundary rather than a blind equal-grid crop.
"""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageChops, ImageDraw
from statistics import median

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/source/commute-gear-actions-v1'
STAGE = ROOT / 'assets/staging/commute-gear-actions-v1'
REVIEW = ROOT / 'output/commute-gear-actions-review'
CELL = 256
SCALE = .45
ANCHOR = (128, 238)
REFERENCE_HEIGHT = 256
CONTACT_BAND = 16
# Frames one and two hold a suit whose dangling legs reach the floor. Their
# lowest alpha rows are not the rabbit's planted shoe, so use inspected sole
# centers and sole-bottom rows for those frames. Values are local to each crop.
MANUAL_FOOT_ANCHORS = {
    ('suit_on', 0): (151, 488),
    ('suit_on', 1): (182, 488),
}
# Other frames use the median center of the lowest 16 source-alpha rows. The
# raised helmet changes the silhouette top, but not its ground contact.
ROWS = [
    ('suit_on', 'equip-suit-alpha-v2.png', 0, 512, 1.2),
    ('zip_up', 'equip-suit-alpha-v2.png', 512, 1024, .8),
    ('boots_gloves', 'gloves-helmet-source-v1.png', 0, 495, .7),
    ('helmet_on', 'gloves-helmet-source-v1.png', 495, 1024, 1.0),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua(value):
    if value is None:
        return 'nil'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return '{' + ','.join(lua(item) for item in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(key) + ']=' + lua(item) for key, item in value.items()) + '}'
    raise TypeError(type(value))


def scoped_color_masks(crop, action, frame):
    """Build fur/overalls masks from color plus safe exposed-body regions.

    The head region cannot overlap the leather. Paw pixels use a narrower,
    brighter orange selection in the upper-body band. Blue overalls use a
    separate blue-only mask. These channels are applied only by gear_action_art.
    """
    alpha = crop.getchannel('A')
    hue, saturation, value = crop.convert('RGB').convert('HSV').split()
    visible = alpha.point(lambda a: 255 if a > 16 else 0)

    def between(channel, low, high):
        return channel.point(lambda v: 255 if low <= v <= high else 0)

    def minimum(channel, threshold):
        return channel.point(lambda v: 255 if v >= threshold else 0)

    head_hue = between(hue, 15, 22)
    head_sat = minimum(saturation, 80)
    head_val = minimum(value, 80)
    head_color = ImageChops.multiply(ImageChops.multiply(head_hue, head_sat), head_val)
    head_zone = Image.new('L', crop.size)
    head_alpha = visible.crop((0, 0, crop.width, round(crop.height * .31)))
    head_bounds = head_alpha.getbbox()
    head_center = ((head_bounds[0] + head_bounds[2] - 1) * .5 if head_bounds else crop.width * .5)
    head_draw = ImageDraw.Draw(head_zone)
    # The generated head silhouette has two tall ears and a broad lower face.
    # Ellipses leave the brown collar and jacket shoulders outside the mask.
    ear_radius_x = round(crop.width * .09)
    ear_radius_y = round(crop.height * .13)
    face_radius_x = round(crop.width * .18)
    face_radius_y = round(crop.height * .16)
    for center_x, center_y in ((head_center - crop.width * .085, crop.height * .125),
                               (head_center + crop.width * .075, crop.height * .125)):
        head_draw.ellipse((round(center_x - ear_radius_x), round(center_y - ear_radius_y),
                           round(center_x + ear_radius_x), round(center_y + ear_radius_y)), fill=255)
    head_draw.ellipse((round(head_center - face_radius_x), round(crop.height * .265 - face_radius_y),
                       round(head_center + face_radius_x), round(crop.height * .265 + face_radius_y)), fill=255)
    if action == 'helmet_on' and frame >= 1:
        # Frame two lifts the shell over the head; keep it out of the fur mask.
        # Frames three and four close the helmet and enclose the rabbit's face.
        if frame >= 2:
            head_zone = Image.new('L', crop.size)
        else:
            ImageDraw.Draw(head_zone).rectangle((0, 0, crop.width - 1,
                                                  round(crop.height * .205)), fill=0)
    head = ImageChops.multiply(ImageChops.multiply(visible, head_color), head_zone)

    if action == 'helmet_on':
        # The gloves are leather throughout this strip, so don't let orange
        # highlights on them get mistaken for exposed rabbit paws.
        paws = Image.new('L', crop.size)
    else:
        paw_hue = between(hue, 16, 21)
        paw_sat = minimum(saturation, 220)
        paw_val = minimum(value, 150)
        paw_color = ImageChops.multiply(ImageChops.multiply(paw_hue, paw_sat), paw_val)
        paw_zone = Image.new('L', crop.size)
        ImageDraw.Draw(paw_zone).rectangle((0, round(crop.height * .40), crop.width - 1,
                                           round(crop.height * .66)), fill=255)
        paws = ImageChops.multiply(ImageChops.multiply(visible, paw_color), paw_zone)
    fur = ImageChops.lighter(head, paws)

    blue_hue = between(hue, 132, 174)
    blue_sat = minimum(saturation, 96)
    blue_val = minimum(value, 38)
    overalls = ImageChops.multiply(ImageChops.multiply(ImageChops.multiply(visible, blue_hue), blue_sat), blue_val)
    return fur, overalls


def ground_anchor(crop, action, frame):
    alpha = crop.getchannel('A').point(lambda a: 255 if a > 16 else 0)
    bounds = alpha.getbbox()
    assert bounds, 'empty source frame'
    manual = MANUAL_FOOT_ANCHORS.get((action, frame))
    if manual:
        return manual[0], manual[1], bounds, 'manual_planted_foot'
    contact_y = bounds[3] - 1
    centers = []
    for y in range(max(bounds[1], contact_y - CONTACT_BAND + 1), contact_y + 1):
        row = alpha.crop((0, y, crop.width, y + 1))
        run = row.getbbox()
        if run and run[2] - run[0] >= 4:
            centers.append((run[0] + run[2] - 1) * .5)
    assert centers, 'frame has no ground-contact rows'
    return median(centers), contact_y, bounds, 'lowest_16px_alpha_band'


def main():
    STAGE.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    manifest = {
        'status': 'staged_unapproved', 'generator': 'built-in imagegen',
        'direction': 'southeast', 'frameSize': [CELL, CELL],
        'anchor': list(ANCHOR), 'groundAnchorMethod': 'manual planted-foot centers for suit_on frames 1-2; median center of lowest 16 source-alpha rows elsewhere',
        'uniformSourceScale': SCALE,
        'runtimeIntegrated': False, 'actions': {},
        'pending': [
            'Other facing directions or an explicit turn-to-dress presentation',
            'Removal/glove removal continuity and mount/ignition/dismount artwork',
            'Boot fastening is not shown; the staged boots_gloves strip only depicts gloves.',
        ],
    }
    contact = Image.new('RGB', (4 * CELL, 4 * (CELL + 24)), '#506978')
    mask_contact = Image.new('RGB', (4 * CELL, 4 * (CELL + 24)), '#506978')
    draw = ImageDraw.Draw(contact)
    mask_draw = ImageDraw.Draw(mask_contact)
    preview = []
    durations = []
    action_registration = {'status': 'staged_unapproved', 'character': 'rabbit-worker',
        'frameSize': CELL, 'anchor': list(ANCHOR), 'referenceHeight': REFERENCE_HEIGHT,
        'direction': 'southeast', 'actions': {}}
    for row, (name, filename, top, bottom, duration) in enumerate(ROWS):
        source = SOURCE / filename
        im = Image.open(source).convert('RGBA')
        assert im.size == (1536, 1024), (filename, im.size)
        assert im.getchannel('A').getextrema()[0] == 0, filename
        strip = Image.new('RGBA', (CELL * 4, CELL))
        mask_strip = Image.new('RGBA', (CELL * 4, CELL), (0, 0, 0, 255))
        records = []
        for frame in range(4):
            left, right = frame * 384, (frame + 1) * 384
            # The held helmet projects two opaque pixels past x=384. Preserve
            # it with its owner; do not carry that sliver into the next frame.
            if name == 'helmet_on' and frame == 0:
                right = 392
            elif name == 'helmet_on' and frame == 1:
                left = 392
            rect = (left, top, right, bottom)
            crop = im.crop(rect)
            assert crop.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox(), (name, frame)
            contact_x, contact_y, source_bounds, anchor_method = ground_anchor(crop, name, frame)
            fur_mask, overall_mask = scoped_color_masks(crop, name, frame)
            alpha = crop.getchannel('A')
            edges = [(0, 0, crop.width, 1), (0, crop.height - 1, crop.width, crop.height),
                     (0, 0, 1, crop.height), (crop.width - 1, 0, crop.width, crop.height)]
            assert all(alpha.crop(edge).getextrema()[1] <= 16 for edge in edges), (name, frame, 'source boundary clips figure')
            scaled = crop.resize((round(crop.width * SCALE), round(crop.height * SCALE)), Image.Resampling.LANCZOS)
            scaled_fur = fur_mask.resize(scaled.size, Image.Resampling.LANCZOS)
            scaled_overalls = overall_mask.resize(scaled.size, Image.Resampling.LANCZOS)
            source_anchor_x = left + contact_x
            source_anchor_y = top + contact_y
            position = (ANCHOR[0] - round(contact_x * SCALE), ANCHOR[1] - round(contact_y * SCALE))
            tile = Image.new('RGBA', (CELL, CELL))
            tile.alpha_composite(scaled, position)
            mask_rgba = Image.merge('RGBA', (scaled_fur, scaled_overalls,
                Image.new('L', scaled.size), Image.new('L', scaled.size, 255)))
            mask_tile = Image.new('RGBA', (CELL, CELL), (0, 0, 0, 255))
            mask_tile.alpha_composite(mask_rgba, position)
            bounds = tile.getchannel('A').point(lambda v: 255 if v > 16 else 0).getbbox()
            assert bounds and min(bounds[0], bounds[1], CELL - bounds[2], CELL - bounds[3]) >= 2, (name, frame, bounds)
            strip.alpha_composite(tile, (frame * CELL, 0))
            mask_strip.alpha_composite(mask_tile, (frame * CELL, 0))
            tile_x, tile_y = frame * CELL, row * (CELL + 24)
            draw.line((tile_x, tile_y + ANCHOR[1], tile_x + CELL, tile_y + ANCHOR[1]),
                      fill='#91b4ad', width=1)
            draw.line((tile_x + ANCHOR[0], tile_y + ANCHOR[1] - 6,
                       tile_x + ANCHOR[0], tile_y + ANCHOR[1] + 6), fill='#c5df8c', width=1)
            contact.paste(tile, (tile_x, tile_y), tile)
            draw.text((frame * CELL + 8, row * (CELL + 24) + CELL + 4), f'{name} {frame + 1}', fill='white')
            preview_mask = Image.new('RGBA', (CELL, CELL), '#506978')
            preview_mask.alpha_composite(tile)
            red = Image.new('RGBA', (CELL, CELL), (240, 70, 55, 0))
            red.putalpha(mask_tile.getchannel('G').point(lambda v: int(v * .68)))
            green = Image.new('RGBA', (CELL, CELL), (45, 235, 110, 0))
            green.putalpha(mask_tile.getchannel('R').point(lambda v: int(v * .68)))
            preview_mask.alpha_composite(red)
            preview_mask.alpha_composite(green)
            mask_contact.paste(preview_mask.convert('RGB'), (tile_x, tile_y))
            mask_draw.text((frame * CELL + 8, row * (CELL + 24) + CELL + 4), f'{name} {frame + 1}', fill='white')
            bg = Image.new('RGBA', (CELL, CELL), '#506978')
            bg.alpha_composite(tile)
            preview.append(bg.convert('RGB'))
            durations.append(round(duration * 1000 / 4))
            records.append({'sourceRect': list(rect), 'sourceGroundAnchor': [source_anchor_x, source_anchor_y],
                'groundAnchorMethod': anchor_method, 'bounds': list(bounds),
                'furMaskPixels': sum(fur_mask.histogram()[17:]),
                'overallsMaskPixels': sum(overall_mask.histogram()[17:])})
        target = STAGE / f'{name}_southeast.png'
        mask_target = STAGE / f'{name}_southeast_mask.png'
        strip.save(target)
        mask_strip.save(mask_target)
        visible_heights = [record['bounds'][3] - record['bounds'][1] for record in records]
        normalization_height = median(visible_heights)
        manifest['actions'][name] = {
            'path': str(target.relative_to(ROOT)), 'duration': duration, 'frameCount': 4,
            'maskPath': str(mask_target.relative_to(ROOT)), 'normalizationHeight': normalization_height,
            'source': str(source.relative_to(ROOT)), 'sourceSha256': sha(source),
            'sha256': sha(target), 'maskSha256': sha(mask_target), 'frames': records,
        }
        action_registration['actions'][name] = {
            'path': str(target.relative_to(ROOT)).replace('\\', '/'),
            'maskPath': str(mask_target.relative_to(ROOT)).replace('\\', '/'),
            'duration': duration, 'frameCount': 4, 'normalizationHeight': normalization_height,
            'frames': [{'bounds': record['bounds'], 'groundAnchor': list(ANCHOR),
                        'groundAnchorMethod': record['groundAnchorMethod'],
                        'furMaskPixels': record['furMaskPixels'],
                        'overallsMaskPixels': record['overallsMaskPixels'],
                        'sourceGroundAnchor': record['sourceGroundAnchor']}
                       for record in records],
            'sourceSha256': sha(source), 'sha256': sha(target), 'maskSha256': sha(mask_target),
        }
    contact.save(REVIEW / 'equip-contact.png')
    mask_contact.save(REVIEW / 'equip-mask-contact.png')
    # Review aid only; generated GIF timing is not runtime acceptance.
    durations[-1] += 900
    preview[0].save(REVIEW / 'equip-preview.gif', save_all=True, append_images=preview[1:], duration=durations, loop=0)
    (STAGE / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (STAGE / 'registration.lua').write_text('-- Generated by compile_gear_actions.py; staged review art only.\nreturn ' + lua(action_registration) + '\n', encoding='utf-8')
    (REVIEW / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Staged four action strips / 16 frames with planted-foot registration and scoped color masks; runtime unchanged.')


if __name__ == '__main__':
    main()
