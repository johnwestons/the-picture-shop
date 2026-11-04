# Cutter motion detail sprites

Generated with the built-in ImageGen tool for the cutter GUI, using the existing `polar-operator-console.png` as the style and scale reference. The POLAR 115 XT photo and project brief informed the component separation and placement; the user's correction informed the diagonal knife edge and shearing motion.

## Assets

- `clamp.png` — isolated brushed-steel hold-down beam with pressure pads.
- `blade.png` — isolated guillotine knife with a diagonal cutting edge.
- Runtime copies: `assets/generated/cutter-clamp-detail-v1.png` and `assets/generated/cutter-blade-detail-v1.png`.

## Prompt notes

The clamp prompt requested a low-profile horizontal pressure beam, dark front face, underside rubber pads, screws, and bevels; it explicitly excluded the fixed gold rail, complete head, paper, and table.

The blade prompt requested the actual knife only, with a diagonal sharpened edge so one side enters the stack first. The animation adds a short lateral sweep during descent, holds through the cut, then returns the blade.

Both sprites use a transparent background and were authored at 2172 × 724 pixels. The in-game renderer scales them down as textured moving components, rather than treating atlas translations as authored animation frames.
