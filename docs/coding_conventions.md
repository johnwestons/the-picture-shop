# Picture Shop coding conventions

These rules adapt the useful boundaries and stabilization practices from the neighboring Mouse Frontier project.

- `main.lua` is only a LÖVE callback adapter. Game state and behavior belong in modules.
- One module owns each concern: application routing, state, save files, assets, viewport, input, navigation, interactions, world simulation, economy, machine simulation, and each screen renderer.
- Modules return a local table and avoid creating globals. Shared state is passed explicitly or owned by the application module.
- Simulation changes happen in `update` or input handlers. Drawing functions do not change game state.
- The game renders to a fixed 960×678 logical canvas. `src/viewport.lua` applies uniform scaling and letterboxing.
- Raster art uses nearest-neighbor filtering. Asset paths and atlas contracts are centralized in `src/assets.lua`.
- Core assets are validated during load and in the smoke test. Missing or malformed assets are reported with their path.
- Save payloads are versioned and validated before entering game state. Each meaningful economy or production result triggers a save.
- Interactions are selected by `src/interaction.lua`; walkability is owned by `src/navigation.lua` and samples the character's feet against the mask.
- New gameplay needs a deterministic smoke-test checkpoint before it is considered stable.
- Reference art and generated drafts are never overwritten during preparation. Promoted assets receive explicit stable filenames.

## Module map

- `src/app.lua`: composition root and screen routing
- `src/state.lua`: new-game state and save application
- `src/save.lua`: three versioned local save slots
- `src/save_schema.lua`: persistent defaults, migrations, nested validation, and reconciliation
- `src/assets.lua`: loading, validation, atlas quads, nearest filtering
- `src/input.lua`: keyboard routing
- `src/navigation.lua`: walkmask and fixed-obstacle checks
- `src/interaction.lua`: proximity selection and prompts
- `src/pallet_state.lua`: legal pallet locations, ownership transitions, invariants, and reconciliation
- `src/world.lua`: player/world update and rendering
- `src/shop.lua`: economy rules
- `src/machine.lua`: Polar 115 simulation state
- `src/screens/`: title, HUD, shop, and machine presentation
- `src/smoke.lua`: deterministic in-engine smoke checks
# Sprite Rendering

- Do not draw artificial circular or elliptical shadows beneath sprites.
- Use transparent sprite sheets and size collision footprints to the visible pixels touching the floor, never to the whole source frame.
