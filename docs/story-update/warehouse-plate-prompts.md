# Warehouse restoration plate generation

Tool: built-in ImageGen, image-edit mode. Each result was copied into `assets/generated/warehouse-condition-v1/`. All plates are 1536×1024. The original authored `warehouse-lobby-seating-v5-three-tier.png` remains the restored, lights-on plate.

## Restored, lights off

Edit target: original authored warehouse sprite.

Prompt: Create a lights-off version of this exact room. All five ceiling and wall lamps are unlit; remove yellow bulbs, wall glows, and golden floor reflections. Turn the office monitor off. Keep readable muted natural daylight. Preserve camera, framing, dock door, rack structure, office doorway, couch, desk, floor seams, yellow safety lines, and every collision boundary. Do not add or remove objects, dirt, water, people, text, or props. Match the original hand-painted style and align closely for runtime switching.

## Worn, lights off

Edit target: restored, lights-off plate above.

Prompt: Show the same warehouse after ten years closed: faded chipped wall paint, rust and chipped rack paint, dusty worn matte concrete, subtle old water staining near the office, scuffed safety paint, and slightly weathered furniture. Keep lamps and monitor off, with no golden glows or reflections. Make it neglected but repairable. Preserve camera, framing, dock and rack geometry, office, couch, desk, floor seams, walkable space, and collision boundaries. Do not add rubble, blocked paths, broken racks, people, new props, puddles, signs, or text. Match the original hand-painted style and close plate registration.

## Worn, lights on

Edit target: worn, lights-off plate above.

Prompt: Turn on the original overhead and wall lamps and office monitor. Add their warm pools of light and reflections on the still worn matte floor. Preserve all worn paint, rust, weathered furniture, scuffed safety paint, and staining. Keep camera, framing, dock and rack geometry, office, couch, desk, floor seams, walkable space, and collision boundaries unchanged. Do not add or move objects, people, puddles, labels, or text. Match the hand-painted style and align closely with the worn, lights-off plate.

The sprite variants control baked lighting and wear. Floor grime, blue-gray oily standing water, fading footprints, and small sparks at the existing breaker are procedural runtime layers.
