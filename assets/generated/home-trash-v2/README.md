# Trash pickup and holding layers

Four authored body phases (pickup, rise, hold, settle), each with eight views in
E, SE, S, SW / W, NW, N, NE order. The separate bag atlas has matching views.
Every source PNG is copied byte for byte from ImageGen; the manifest records
prompts, source locations, dimensions, alpha range and hashes.

`src/home_trash_registration.lua` registers each planted foot and shared knot
grip. `src/home_trash_art.lua` selects an intro once and then alternates the two
hold poses using the existing authoritative chore timer. All views use the same
bag scale, hanging upright from its knot. Rear views draw it behind the body;
front views redraw a small finger patch over the knot. Colorways affect only
the body. Four body atlases and one prop atlas are the bounded resource set.

Body quads exclude eight pixels at either horizontal cell edge and the final
twelve pixels below each cell to avoid neighbouring ear/tail fragments. PNGs
are unchanged. Coupled `study` images are design references, not runtime art.

The current chore is stationary at the apartment entrance: this is a pickup
and hold animation, not a walking carry cycle. Moving cancels its presentation
and normal chore rules govern completion. Other household animation families
remain tracked in `docs/weekend_home_plan.md`.
