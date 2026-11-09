# Kei delivery truck turntable candidates

This is an art-only starting point for a Japanese kei-class delivery truck. It
has an off-white cab-over cab and an empty charcoal drop-side bed, for the
smaller deliveries described in the project brief. Its target visual size is
about 64% of the box truck's length and 70% of its width.

Both camera elevations have the same view count: **64 frames each**, arranged
as four 4×4 contact-sheet pages with 16 views per page. Both start at the rear,
rotate clockwise in 5.625-degree steps, and use the same page-to-angle mapping.

| View | Camera elevation | Frame pages | Raw page canvas sizes |
|---|---:|---|---|
| Isometric | about 32° | 1–16, 17–32, 33–48, 49–64 | 1254×1254 each |
| Chase | about 8° | 1–16, 17–32, 33–48, 49–64 | 1619×971, 1619×971, 1620×971, 1619×971 |

The existing box-truck manifest also declares 64 isometric and 64 chase frames;
the project's atlas validator confirms both sets have 64 distinct, unclipped
frames. Its counts are even; the mismatch noticed in play may come from angle
continuity between the elevations, which can be checked during later art QA.
This new set is a visual candidate only. Its generated contact sheets do not
yet use the exact runtime page dimensions, and a few frames show edge fringing.
Crop/scale normalization and frame-by-frame cleanup belong in the asset
preparation pass before any game wiring.

## First-person interior plan

When this vehicle is wired into the game, reuse the box truck's existing
first-person cab implementation and interior art. The shared setup is
`src/commute/truck_cockpit.lua`, with the dashboard overlay at
`assets/commute/truck/cockpit-overlay-v2.png`, the shell and controls in
`assets/commute/truck/interior-v2/`, and the existing headliner and driver seat
in `assets/commute/truck/interior-v1/`. This keeps the kei truck on the same
dashboard controls, camera, and interior rendering path without creating a
second set of cabin sprites. The truck remains art-only until its exterior
turntable pages are normalized and integrated.

## Generation prompt

Create a transparent 4×4 sheet of sixteen consecutive, distinct views of the
same compact Japanese kei cab-over utility truck. Use a single off-white cab,
empty charcoal drop-side flatbed, compact wheels, subtle red tail lamps, amber
indicators, realistic pre-rendered game art, and no branding, cargo, people, or
scene. Keep the kei truck around 64% of the box truck's length and 70% of its
width. Match the existing truck art's light, scale, and shared tire anchor.

Generate four pages per camera: frame 1 is the rear; each page covers sixteen
clockwise 5.625° steps, with page starts at 0°, 90°, 180°, and 270°. Generate
one full set at the elevated 32° isometric camera and one at the low 8° chase
camera. Keep every frame's vehicle design, scale, ground contact, and lighting
consistent. Use a transparent background with only a tight tire-contact shadow.

## Files

- `turntables/isometric-64-1.png` through `isometric-64-4.png`
- `turntables/chase-64-1.png` through `chase-64-4.png`
- `turntables/manifest.json`

No vehicle behavior or build registration is included in this art pass.
