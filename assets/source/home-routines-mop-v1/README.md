# Warehouse mop animation source

The mop atlas was generated with the built-in image generation tool as a non-destructive edit of the existing eight-direction broom atlas. The source PNG is retained here. The runtime copy is `assets/generated/home-routines-v2/mop-eight-directions-v1.png`; it is byte-identical and remains in the existing 4-column by 2-row, 1536x1024 layout.

The character frames, hand grips, animation sequence (`1,2,3,4,3,2`), and six-frame-per-second cadence are reused from the reviewed apartment sweep animation. The mop head stays centered on the former broom floor contact so the existing 32 directional grips remain aligned.

Prompt used:

```text
Use case: precise-object-edit.
Asset type: transparent 8-direction game prop sprite sheet for a 2D isometric game.
Input image: Image 1 is the exact existing eight-direction broom sheet and is the edit target.
Primary request: replace each broom with a floor mop while keeping this sheet directly usable by the existing eight-direction sweeping animation.
Composition/framing: preserve the original 1536x1024 canvas and exact 4-column by 2-row grid of 384x512 cells. Keep exactly one complete tool in each cell, in the same order and directions as Image 1. Keep each long shaft at the same angle, length, endpoint positions, and scale as its corresponding broom so it still meets the character's registered two-hand grips. Keep the mop head centered on the original broom-head floor contact point and at the same overall size/grounding in each cell. Preserve generous transparent gutters and the original orthographic/isometric camera.
Subject: a practical long-handled wet-floor mop, with the same warm wood handle, a compact gray metal collar, and a clearly recognizable soft off-white cotton/string mop head with a restrained pale blue damp sheen. Show correct foreshortening and front/back views for each of the eight directions. The head must read as soft mop strands, never straw bristles or a broom fan.
Style/medium: match Image 1's polished painterly game-prop rendering, dark clean outline, soft dimensional highlights, and fixed upper-left light.
Lighting/mood: soft upper-left studio light, neutral.
Constraints: edit only the eight tools. Preserve all eight orientations, original cell layout, object scale, shaft endpoints, ground contacts, visual style, and true transparent alpha. No character, hands, floor, cast shadow, background, glow, haze, water puddles, checkerboard, grid, text, labels, numbers, or extra items. Do not rotate, duplicate, move, resize, crop, or change the canvas.
```
