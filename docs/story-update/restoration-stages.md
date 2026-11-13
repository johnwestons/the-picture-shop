# Warehouse restoration plate sequence

The warehouse now uses five fixed visual stages. The stage is derived from saved work rather than stored as a second progress flag. This makes save reload and host/guest rendering deterministic. Utility service, breaker repair and the wall switch select the on/off plate independently; stage 0 also has an on plate because a player may repair the breaker before cleaning.

| Stage | Trigger | What changes in the plate | Lights off | Lights on |
| --- | --- | --- | --- | --- |
| 0 — abandoned | Story shop begins | Chipped paint, worn rack, scuffed dock; detail stays sharp and the floor stays readable | [0 off](../../assets/generated/warehouse-condition-v2/stage0-off.png) | [0 on](../../assets/generated/warehouse-condition-v2/stage0-on.png) |
| 1 — west cleaned | Clean west dock floor | Dock slats, left wall and left shelf lose surface grime; paint chips remain | [1 off](../../assets/generated/warehouse-condition-v2/stage1-off.png) | [1 on](../../assets/generated/warehouse-condition-v2/stage1-on.png) |
| 2 — center cleaned | Clean center rack floor | Racks, shelves and rear wall are wiped; worn paint remains | [2 off](../../assets/generated/warehouse-condition-v2/stage2-off.png) | [2 on](../../assets/generated/warehouse-condition-v2/stage2-on.png) |
| 3 — east cleaned | Clean east floor | Office-side baseboards and furniture are cleaned; wall chips remain | [3 off](../../assets/generated/warehouse-condition-v2/stage3-off.png) | [3 on](../../assets/generated/warehouse-condition-v2/stage3-on.png) |
| 4 — repainted | Touch up the walls and racks | Fully restored surfaces | [4 off](../../assets/generated/warehouse-condition-v2/stage4-off.png) | [Original authored plate](../../assets/generated/warehouse-lobby-seating-v5-three-tier.png) |

West, center and east floor cleaning are ordered. Repainting becomes available after all three. The two oily water puddles remain separate saved cleanup actions at their own walk-up locations. Water connection, power connection and breaker repair can happen before or during cleanup. A grand opening remains a separate action after the machines are serviced and the floor and puddles are clean. Procedural floor grime and oily blue-gray water still do not get baked into these background plates.

The worn lights-off image from v1 is retired from the runtime. The new stage 0 uses localized paint wear, dark clear shadows and intact texture; there is no uniform dusty veil. The broad floor remains free of baked puddles so cleaning overlays can disappear cleanly. Every stage uses the same walkmask and world coordinates. On/off variants change baked lamp and monitor lighting only.

The renderer loads the first needed condition plate before showing a resumed Story warehouse, then streams later plates on demand and retains at most two generated plates at once. While a later plate decodes, the previous condition plate remains visible. The original fully restored, lights-on background remains managed by the normal asset pack.

## Image generation record

Mode: built-in ImageGen edit. All outputs are 1536×1024 PNGs copied into `assets/generated/warehouse-condition-v2/`. No new scene geometry, props or collision boundaries were requested.

- **Stage 0 off:** edit the original authored warehouse plate. Make lamps, monitor and their reflections off; show modest local wall chips, rack wear and dock scuffs. Keep diffuse natural ambient light, sharp microtexture and clear shadows. Exclude fog, haze, airborne dust, blur, global tint, rubble and floor puddles. A second edit removed an overly strong diagonal sunlight beam while retaining the crisp worn surfaces.
- **Stage 1 off:** edit stage 0 off. Clean only the west dock wall, door slats and left shelf. Preserve paint chips, center/east wear, furniture geometry and off lighting.
- **Stage 2 off:** edit stage 1 off. Clean center rack shelves and rear-wall surface grime while retaining west progress and chipped paint.
- **Stage 3 off:** edit stage 2 off. Clean the office-side threshold, baseboards, wall stains and furniture; keep paint wear for the final action.
- **Stages 0–3 on:** edit each corresponding off plate, using an existing lit plate only to reference lamp locations. Turn on the original wall/ceiling lamps and monitor with local warm pools and subtle reflections. Preserve that stage's exact wear and cleanup state. Exclude global amber wash, haze, fog and soft focus.
- **Stage 4 off:** reuse the existing restored lights-off edit; stage 4 on remains the original authored warehouse art.

After in-game review, stage 1 was edited again to clean the west floor, stage 2 to clean west and center while leaving east stained, and stage 3 to make the entire floor clean while retaining chipped walls. Each lit partner was regenerated from its corrected off plate. These final correction prompts used the next stage only as a floor-texture reference and explicitly retained the edit target's tile seams, fixtures and wear.

## Review gates

Compare the plates at 960×678 in the actual game, including mobile framing. Inspect dock and office edges, rack registration, floor seams, breaker position, seated visitors and stocked racks across swaps. Generated edits can subtly shift painted details even when the layout is fixed; those seams need a final art pass before Story mode is exposed. Check that a stage change removes only the intended grime and that switching lights never changes the restoration stage. Keep all work actions and exits reachable while unpowered.
