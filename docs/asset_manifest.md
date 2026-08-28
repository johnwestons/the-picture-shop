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
| `characters/rabbit-worker` directional idles / walks | five 1024x512, 2x1 / five 4096x512, 8x1 strips | Paired eight-sector streamed player movement pack |
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
| `palletWorkOrderPaper` | 1536x1024 | Pallet-attached work-order screen background |

Configured `artwork:*` images are 128x128 library entries resolved by saved artwork key and rotated through job offers. Visitor character action strips are validated from `Config.characters`, loaded only when that action is drawn, normalized from precomputed alpha bounds, and released when the visitor leaves.

## Screen packs

| Pack | Runtime IDs | Residency |
|---|---|---|
| Menu | `polarOperatorConsole` (768x512), `cutterControlButtons` (512x128) | Title only |
| Cutter | Menu art, `cutterClamp` / `cutterBlade` (3840x512), `cutterMaintenanceOil` (512x512), `cutterMaintenanceTools` (768x512, 3x2), and `cutterMaintenanceScenes` (1024x768, 2x2) | Cutter console and maintenance minigames |
| Wrapper | `loadedPaperPallet` (256x256) | Wrapper console only |
| Press | `pressProcessStage1` ... `pressProcessStage4`, cut from `press-process-stages-atlas-v3.png` (1254x1254, 2x2); `pressHandbookPage1` ... `pressHandbookPage10`, cut from `heidelberg-operator-handbook-atlas-v2.png` (2560x1024, 5x2); `pressSetupInteraction1` ... `pressSetupInteraction6`, cut from `heidelberg-setup-interactions-atlas-v2.png` (1536x1024, 3x2) | Windmill previews, illustrated Help handbook, and six setup minigames |

Menu, cutter, wrapper, and press packs are mutually exclusive. Transition tests verify load, replacement, and release. The smoke gate enforces a retained startup set below 100 MiB with no character action loaded.

## Deferred source and backlog art

The base Polar presentation sheet, empty pallet, paper stack, storage boxes, and toolbox images remain approved backlog assets but have no runtime loader until a renderer or placement system uses them. `heidelberg-windmill-plate-concept-v1.png` remains a source concept; the live Windmill uses the blank four-stage process atlas so each job's actual art can be composited at runtime. Other machine references remain outside the live contract. Keeping them in the raster doctor catches damaged source files without spending runtime memory.

When promoting an asset, add one stable runtime ID, an exact dimension/grid contract, a real renderer, a named smoke check, and an asset-doctor check. Remove the load when its last renderer is removed.

## Polar 115 lubrication minigame

Built-in ImageGen stylized-concept tool prompt: Create an exact 3x2 pixel-art maintenance-tool atlas with three aligned lever positions of the same high-pressure grease gun, followed by a lint-free rag, red lockout padlock/key/tag, and capped grease cartridge. No people, text, logos, or extra tools. The generated source is preserved in the Codex generated-image store; the deterministic cutter-maintenance builder installs it as `cutter-maintenance-tools-atlas.png` (768x512).

Built-in ImageGen stylized-concept scene prompt: Create an exact 2x2 pixel-art service-view atlas of a powered-down Polar-style 115 cutter: rear backgauge rails with two nipples, front knife/clamp guides with two fittings, side eccentric/crank access with two fittings, and gearbox with a readable oil sight glass below midpoint. No people, tools, text, logos, or UI. The generated source is preserved in the Codex generated-image store; the builder installs it as `cutter-maintenance-scenes-atlas.png` (1024x768).

The player procedure uses lockout/tagout, grease-gun preparation, fitting cleaning, coupling and 2–3 lever strokes, plus gearbox sight-glass inspection. Optional central-lubrication cutters instead require pumping until the indicator flashes twice. Hydraulic oil remains technician-only.

## Windmill print-process atlas

Built-in ImageGen prompt sequence: create a transparent 2x2 semi-pixel-art/isometric atlas matching the shop, with a client proof/file board, plate in chase, proof beneath a loupe, and finished stack; then remove every baked artwork mark from the four printable surfaces so the game can overlay the active job image; finally extract the checkerboard into true alpha without changing the objects, blank surfaces, crop marks, loupe, shadows, or lighting. No readable text, logos, watermark, or baked client art. The installed RGBA asset is `assets/generated/press-process-stages-atlas-v3.png`.

## Windmill operator-handbook atlas

Built-in ImageGen transformed ten tightly cropped, face-free photographs from *Manual for the Operation of Heidelberg Platens* into a 5x2 educational pixel-art atlas. The original camera angles and machine geometry are retained, while every visible hand wears a fitted brown leather glove. The panels show motor controls, stock loading, chase lockup, tympan packing, form rollers, ink flow, feeder suction, register guides, washup, and lubrication. Runtime text supplies the explanations and source note so the wording remains readable and maintainable. The installed asset is `assets/generated/heidelberg-operator-handbook-atlas-v2.png`.

## Pallet work-order sheet

Built-in ImageGen stylized-concept prompt: create a blank vintage industrial work-order sheet that looks physically attached to a paper pallet, nearly front-facing and landscape-oriented, with warm ivory fibers, restrained age marks, worn edges, corner folds, staple marks, faint blank form rules, and generous clear regions for runtime text and client art. Match the detailed semi-pixel-art warehouse style. Use true transparency outside the paper and include no words, letters, numbers, logos, handwriting, people, or baked client artwork. The generated checkerboard border is deterministically converted to true alpha by `tools/prepare_pallet_work_order_paper.py`; the installed asset is `assets/generated/pallet-work-order-paper-v1.png`.

Work-order copy uses the Apache-licensed Special Elite typeface from Google Fonts. The font and its license are bundled in `assets/fonts/` so the screen keeps its typewriter character offline.
