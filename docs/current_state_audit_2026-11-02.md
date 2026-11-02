# Current game-state audit — 2026-11-02

## Scope

Reviewed the apartment/home loop, both commute directions, client/host state flow, save and rendering bounds, and the current broad smoke suite. Changes below were made against the current branch and verified with fresh disposable test identities.

## Findings fixed

### Commute rider jitter

The durable `shop_state` participant snapshot is sent at 4 Hz, while ordinary player position snapshots are sent at 12 Hz and interpolated on clients. The commute view used the slower durable rider coordinates directly, so remote riders could visibly step between snapshots even though the main avatar was smooth.

The commute renderer now overlays the active rider's visual position with the corresponding interpolated player position. It uses a shallow visual copy and leaves the durable participant, vehicle state, and host authority untouched. This adds no network messages and keeps the durable route/session state as the source of truth. A regression check covers the visual/authoritative separation.

### Apartment appliance placement and staging

Furniture placement accepted stoves and refrigerators away from their authored hookups. Delivered appliances could also be staged in a general living-room space, where they were unusable. Placement now requires the exact appliance hookup point; delivery staging tries that point and its authored facing first, leaving the appliance in storage if it cannot be staged safely.

Cooking poses support all eight authored directions through stove approach points. The expanded diagonal approach set is limited to stoves, so unrelated furniture does not pay for extra per-frame route checks.

### Apartment rendering and TV use

The washing-machine body and laundry prop renderer iterated direction names as if they were view records. Both now resolve the cached view record before drawing.

While a resident watched television, the activity menu showed only “stop”; the TV's off command was hidden. The active watch menu now exposes the off action for the TV being watched, and the session ends when its view becomes invalid.

### Authoritative purchase and worker state

Remote office checkout used the catalog list price while its cart validator compared against the current host sale price. Valid orders during a sale were rejected. The host now resolves the current authoritative retail price when normalizing the cart.

Employee cutter, press, and wrapping skill gains now record one award per employee, job, and stage. Repeated operation starts cannot award the same stage twice, and the award travels with the shared job state.

## Performance and state bounds reviewed

- Apartment furniture limits stay bounded at 128 owned objects and 48 placed floor objects.
- Apartment fixture meshes are cached for one active apartment/floor image. Switching apartments or clearing the renderer releases those meshes and routine/art caches.
- Commute terrain mesh creation is capped at 10 chunks per update and a soft 6 ms budget after the first chunk. Old chunks are released after 120 render serials without use.
- Commute vegetation keeps at most 256 generated patches, with patch eviction as the rider moves.
- Gameplay save and image-loading pipelines retain their existing background/coalescing and bounded-upload behavior. Their scope and measurements are recorded in [the save and cold-image stall report](save_image_stalls_2026-10-29.md).

## Verification

- Apartment focus: complete, including apartment rendering, delivery and furnishing, hookups, cooking, desk/surface placement, laundry, dining, utilities, shared sleep, multiplayer state, and save/load.
- Commute runtime/session focus: complete. Both home-to-work and work-to-home routes were ridden through arrival and dismount, with bridge crossings and multiplayer departure, late join, reconnect, stale-command, and host-arrival checks.
- Full smoke suite: complete with three render frames and `SMOKE_OK`.
- Output reports were written under `output/game-state-audit-20261102-1255/` during the run. They are local test artifacts and are not part of the source commit.

## Measurement limits

The current Windows LÖVE environment has no attached Android device. This audit verifies bounded work, state consistency, route behavior, and render completion; it does not claim new Android FPS, GPU frame-time, thermal, or memory measurements. The available Windows crowded-shop and save/image measurements, including their limits, are documented in [the late-game performance report](late_game_performance_2026-10-28.md) and [the save/image report](save_image_stalls_2026-10-29.md).

## Commute and apartment visual backlog update

- Commute road actors now draw the selected normal character or the authored suited-rider strips. Five authored camera views cover eight headings through three intentional mirrors. Equip/removal crossfades are presentation-only; individual suit/zipper/boots/gloves/helmet beats still need production art. Non-rabbit riders remain in their selected normal outfit until matching suit assets exist.
- Apartment cup drinking, changing, and food preparation now use directional mug, towel, and ingredient art. Rest/sleep use clock-driven settling and breathing, and watching a powered TV adds a small screen reflection. These effects read existing replicated clock/activity/furniture state only; save schema and network protocol do not change.
- The static commute sprite audit reported 10 animations, zero errors, and one center-jitter warning on east walk. That warning is retained because frame anchors are fixed and shifting them risks foot slide. No audit thresholds were relaxed.
- This visual pass received static code/art review only. No test suite, game launch, Android device run, or device performance measurement was performed for this pass; earlier audit verification above refers to the previously completed runtime/state audit.
- Remaining review: per-step riding-gear art; suited art for other playable character types; a dedicated animated seated TV/sleep set; final warehouse and apartment visual review; Android frame-time, memory, and thermal measurements on device.
