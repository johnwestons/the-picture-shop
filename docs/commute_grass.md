# Procedural commute grass

Adapted on 2026-11-04 from the current sibling project at
`C:/Users/johnw/OneDrive/Documents/ChatGPT/Critter Party`:

| Source | SHA-256 at import |
| --- | --- |
| `src/grass_fields.lua` | `9FB1E7250B3CBCA02ECABE11AEBE477ED32900351FB493A36911B3584FAEDF66` |
| `src/grass_fields.glsl` | `A269EA2980DCFA34BF8DE990B79D24EF2C88D7AE916EC64F1C5B20040F50584B` |

The sibling project was read only. Its static indexed comb meshes, three-band
tapered blades, seeded variation, broad meadow/local cluster masks, tree/log
influence, wind phase and seasonal palette form the implementation here.
No bitmap assets, wildlife simulation or save data were imported.

## Town adaptations

- `src/commute/grass_placement.lua` checks the town's actual grass material
  weight, terrain slope, all overlapping paved/dirt road segments and junctions,
  sidewalk geometry, building foundations, parking/entrance paths and recreation
  clearings. Road priority cannot hide an overlapping trail from the check.
- Each comb reserves a 2 m footprint that includes its blade widths, lean and
  maximum shader wind bend. Road shoulders get an additional 0.65 m gap;
  sidewalks get 0.35 m. Ocean edges get 7 m plus the footprint, while analytic
  rivers/lakes and legacy water samples receive a 4 m water buffer plus it.
  Marshes, rocky/dirt ground and steep slopes are excluded. Tree influence
  increases density only after these placement requirements pass.
- Tree/log anchors come directly from the same seeded foliage candidates,
  independent of sprite streaming or camera history. Grass creates no collision
  obstacles, saved state or network payloads.
- Blades retain 72% of the source height for the motorcycle's scale. Each blade
  root follows the town terrain. Both cameras share the existing depth buffer;
  first person also shares roll-aware projection and headlight illumination.
- The shader applies vertex color once. The source multiplied it twice, which
  produced very dark blades in this game's native captures.
- Grass begins preparing during terrain loading. The 8 m patches use a 32 m
  draw radius, a 196-entry cache and a strict 12 MiB cached mesh limit. Wind
  moves vertices on the GPU. Generation yields between candidate cells and comb
  sections, targets 2.5 ms per prepare, and caps work at 192 resumptions and two
  completed patches per frame. A mesh upload and individual work step are atomic,
  so the time target is not a hard real-time guarantee. Teleports discard partial
  work outside the new view. Resource release is idempotent.

## Verification

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/commute_lab/review_grass.ps1`.
`-UnitOnly` skips the generated-town captures. The November 4 review passed
64 checks, including placement exclusions, native shader color and wind pixels,
independent seeded meshes, full comb/wind footprint, incremental work, teleport
cancellation, cache limits, collision separation and renderer resource behavior.

The review renders a current generated town (seed 4261) in fixed and first-person
views at meadow, road, trail and coastal locations, plus a follow view. Captures
and the report are in `output/grass-review`. The final run reviewed 6,329 comb
sections across these captures and recorded a 4.606 ms peak grass prepare,
compared with 13.936 ms before incremental construction. These are desktop
measurements, not a physical-phone performance claim.

The actual App runtime also passed the existing 96-check scene HUD/camera review
on desktop and simulated mobile after integration. The grass tests are registered
in the regular domain suite; the entire unrelated game suite was not rerun.
