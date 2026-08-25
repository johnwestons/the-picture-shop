# Runtime asset manifest

The runtime boundary is organized by residency pack. `src/assets.lua` validates required dimensions at startup, retains the core set, and loads only the active screen pack. `tools/asset_doctor.py` performs the slower full decode, alpha, grid, and nonempty-cell audit.

## Core world pack

| Runtime ID | Dimensions | Consumer |
|---|---:|---|
| `warehouse` | 1536x1024 | World background |
| `walkmask` | 1536x1024 CPU-only | Navigation and placement |
| `polarDirections` | 4096x512, 8x1 | Eight-way movable cutter |
| `skidWrapperDirections` | 2048x512, 4x1 | Movable wrapper |
| `windmillDirections` | 1536x1024, 2x2 | Four-way movable Windmill |
| `technicianNpcs` | 2048x1024, 4x2 | Mouse and lizard field technicians |
| `rabbit` | 1536x1024, 6x4 | Player animation |
| `loadingBayDoor` | 1300x260, 5x1 | Loading-bay animation |
| `deliveryTruck` | 512x512 | Truck body |
| `truckCargoDoor` | 2560x512, 5x1 | Truck cargo animation |
| `machineFlatbedLoaded` / `machineFlatbedEmpty` | 512x512 each | Machine-delivery truck before/after unload |
| `loadedPaperPalletDirections` | 1024x256, 4x1 | Loose customer pallets |
| `palletJack` / `palletJackLoaded` | 2048x256 each, 8x1 | Eight-way pallet-jack states |
| `wallVentFan` | 288x96, 3x1 | Animated loading-bay wall vent |
| `vendorProductPallets` | 1252x1252, 4x4 | Delivered supply pallets |
| `boxedPaperPalletStages` | 1400x1120, 5x4 | Boxed customer pallets |
| `wrappedPalletStages` | 1536x512, 3x1 | Wrapper progress and completed flat pallets |
| `polarBackButton` | 384x128, 3x1 | Shared Back/Exit control |

Configured `artwork:*` images are 128x128 library entries resolved by saved artwork key and rotated through job offers. Visitor character action strips are validated from `Config.characters`, loaded only when that action is drawn, normalized from precomputed alpha bounds, and released when the visitor leaves.

## Screen packs

| Pack | Runtime IDs | Residency |
|---|---|---|
| Menu | `polarOperatorConsole` (768x512), `cutterControlButtons` (512x128) | Title only |
| Cutter | Menu art, `cutterClamp` / `cutterBlade` (3840x512), `cutterMaintenanceOil` (512x512), `cutterMaintenanceTools` (768x512, 3x2), and `cutterMaintenanceScenes` (1024x768, 2x2) | Cutter console and maintenance minigames |
| Wrapper | `loadedPaperPallet` (256x256) | Wrapper console only |

Menu, cutter, and wrapper packs are mutually exclusive. Transition tests verify load, replacement, and release. The smoke gate enforces a retained startup set below 100 MiB with no character action loaded.

## Deferred source and backlog art

The base Polar presentation sheet, empty pallet, paper stack, storage boxes, and toolbox images remain approved backlog assets but have no runtime loader until a renderer or placement system uses them. `heidelberg-windmill-plate-concept-v1.png` is the approved four-state photopolymer plate concept (blank, exposed relief, mounted, and inked) derived from the supplied tan-plate/blue-base reference. It remains outside the live contract until the guarded Windmill production scene owns a renderer. Picture-press and other machine references remain outside the live contract. Keeping them in the raster doctor catches damaged source files without spending runtime memory.

When promoting an asset, add one stable runtime ID, an exact dimension/grid contract, a real renderer, a named smoke check, and an asset-doctor check. Remove the load when its last renderer is removed.

## Polar 115 lubrication minigame

Built-in ImageGen stylized-concept tool prompt: Create an exact 3x2 pixel-art maintenance-tool atlas with three aligned lever positions of the same high-pressure grease gun, followed by a lint-free rag, red lockout padlock/key/tag, and capped grease cartridge. No people, text, logos, or extra tools. The generated source is preserved in the Codex generated-image store; the deterministic cutter-maintenance builder installs it as `cutter-maintenance-tools-atlas.png` (768x512).

Built-in ImageGen stylized-concept scene prompt: Create an exact 2x2 pixel-art service-view atlas of a powered-down Polar-style 115 cutter: rear backgauge rails with two nipples, front knife/clamp guides with two fittings, side eccentric/crank access with two fittings, and gearbox with a readable oil sight glass below midpoint. No people, tools, text, logos, or UI. The generated source is preserved in the Codex generated-image store; the builder installs it as `cutter-maintenance-scenes-atlas.png` (1024x768).

The player procedure uses lockout/tagout, grease-gun preparation, fitting cleaning, coupling and 2–3 lever strokes, plus gearbox sight-glass inspection. Optional central-lubrication cutters instead require pumping until the indicator flashes twice. Hydraulic oil remains technician-only.
