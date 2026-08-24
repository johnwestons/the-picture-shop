# Runtime asset manifest

The runtime boundary is organized by residency pack. `src/assets.lua` validates required dimensions at startup, retains the core set, and loads only the active screen pack. `tools/asset_doctor.py` performs the slower full decode, alpha, grid, and nonempty-cell audit.

## Core world pack

| Runtime ID | Dimensions | Consumer |
|---|---:|---|
| `warehouse` | 1536x1024 | World background |
| `walkmask` | 1536x1024 CPU-only | Navigation and placement |
| `polarDirections` | 2048x512, 4x1 | Movable cutter |
| `skidWrapperDirections` | 2048x512, 4x1 | Movable wrapper |
| `rabbit` | 1536x1024, 6x4 | Player animation |
| `loadingBayDoor` | 1300x260, 5x1 | Loading-bay animation |
| `deliveryTruck` | 512x512 | Truck body |
| `truckCargoDoor` | 2560x512, 5x1 | Truck cargo animation |
| `loadedPaperPalletDirections` | 1024x256, 4x1 | Loose customer pallets |
| `palletJack` / `palletJackLoaded` | 1024x256 each, 4x1 | Pallet-jack states |
| `vendorProductPallets` | 1252x1252, 4x4 | Delivered supply pallets |
| `boxedPaperPalletStages` | 1400x1120, 5x4 | Boxed customer pallets |
| `polarBackButton` | 384x128, 3x1 | Shared Back/Exit control |

Configured `artwork:*` images are optional library entries resolved by saved artwork key. Visitor character action strips are validated from `Config.characters`, loaded only when that action is drawn, and released when the visitor leaves.

## Screen packs

| Pack | Runtime IDs | Residency |
|---|---|---|
| Menu | `polarOperatorConsole` (768x512), `cutterControlButtons` (512x128) | Title only |
| Cutter | Menu art plus `cutterClamp` and `cutterBlade` (3840x512 each) | Cutter console only |
| Wrapper | `wrappedPalletStages` (1536x512), `loadedPaperPallet` (256x256) | Wrapper console only |

Menu, cutter, and wrapper packs are mutually exclusive. Transition tests verify load, replacement, and release. The measured retained startup set is 42.69 MiB with no character action loaded.

## Deferred source and backlog art

The base Polar presentation sheet, empty pallet, paper stack, storage boxes, and toolbox images remain approved backlog assets but have no runtime loader until a renderer or placement system uses them. Picture-press and other machine references remain outside the live contract. Keeping them in the raster doctor catches damaged source files without spending runtime memory.

When promoting an asset, add one stable runtime ID, an exact dimension/grid contract, a real renderer, a named smoke check, and an asset-doctor check. Remove the load when its last renderer is removed.
