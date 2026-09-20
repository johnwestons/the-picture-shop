# Warehouse expansion, pallet storage and forklift — implementation plan

Prepared September 18, 2026. Scope of this pass: inspect the actual game, establish the implementation/art contracts, generate the first art candidates, and stage the existing Mouse Frontier mechanic. This document is ready to use as an ordered work list. It does not claim the new gameplay or generated sheets are already integrated.

## 1. Non-negotiable design

- Improve screen coverage by changing the warehouse footprint and framing, **not** by enlarging characters, machines, pallets or the pallet jack.
- The corrected base's **bottom is approved**: preserve its two black lower upgrade bays and short, flat front edge exactly. Do not add a projecting apron, ramp, platform or foreground extension. The next base-art revision changes **only the top**, filling the remaining upper black gaps with taller matching warehouse architecture; do not zoom, rescale objects or alter the approved bottom to achieve this.
- The two front-side black areas marked in the supplied screenshot become separate purchasable expansion bays, `front_left` and `front_right`. Both start black, inaccessible and unowned.
- Each bay can be built as open warehouse floor, pallet shelving, or an employee breakroom. These are three choices for each bay, not three interchangeable rectangular stickers.
- A storage module has exactly **two rows × five columns = ten pallet positions**. Empty shelf artwork receives separate pallet sprites. The same contents appear in the isometric world and the front-facing rack interaction screen.
- The **2×5 first-person shelf design is user-approved**. Preserve that design while separating its production layers and registering the ten pallet anchors; approval of the visual design does not make the current source image runtime-ready.
- Ground-level shelf transfers work with the pallet jack or forklift. The upper row requires an owned forklift that the player is actually operating. Owning a forklift does not remotely unlock teleporting stock.
- Show the upper-row limitation before purchase and ask for a purchase confirmation if the forklift is not owned. Five lower slots remain usable without it.
- Forklift movement/ownership follows the existing jack model, with additional fork-height, shelving and two-high floor-stack operations.
- Construction has **four visible stages, each lasting 24 in-game hours**. Completion therefore takes four game days after work begins, excluding appointment delays or blocked access. The present clock is 300 real seconds per game day, about 20 active-play minutes for four days.
- The Mouse Frontier raccoon calls ahead, enters through the front glass entrance, walks to the project, works with genuine tool animations, and leaves through that entrance. Do not spawn him at the loading dock or inside the new room.
- Keep multiplayer host/guest GUI and functionality equal from the beginning. Host authority owns cash, cargo, slot assignments, build times and purchases.

Working assumptions: two bays as drawn; either bay can take any of the three room choices; one construction worker/project active at a time; no offline real-clock construction; one forklift initially; maximum floor stack height two. These can be tuned without redesigning the data model.

## 2. Existing contracts and scale lock

The current background and walk mask are `assets/generated/warehouse-layout-final.png` and `warehouse-layout-final-walkmask.png`, both 1536×1024. `src/world_renderer.lua` maps them to a 960×678 world; this is an existing nonuniform background-only mapping. `src/viewport.lua` letterboxes desktop, while `src/mobile_camera.lua` currently applies automatic fill zoom. Changing only the PNG will not solve every screen shape.

Keep these configuration values and existing visible object heights unchanged:

| Object | Current contract |
| --- | --- |
| Characters | Visible body normalized to 256 source pixels, world draw scale 0.30; about 76.8 world pixels tall |
| Cutter | 512px frame, draw scale 0.272 |
| Wrapper | 512px frame, draw scale 0.22 |
| Windmill | 768×512 frame, draw scale 0.196 |
| Loose pallets | 256px frame, draw scale 0.26 |
| Jack | 256px frame, draw scale 0.416; existing carried-pallet ratio 0.625 |

Implementation approach:

1. Capture before/after sprite bounds at identical resolution and user zoom. Reject unintended changes in character/machine/pallet/jack pixel size.
2. Keep the present 960×678 coordinate space as the core-layout reference. Introduce explicit world bounds and a background source-to-world transform rather than stretching a new image to whatever window happens to be open.
3. Use the corrected, bottom-approved base as the registration reference. Retain its black lower upgrade bays, short flat front edge, dock, office, front entrance, phone, customer seating and existing valid floor anchors. Remake only the upper region with taller matching walls/roof architecture that fills the upper black gaps at the same texture and object scale. Do not extend the bottom into an apron or ramp. Preserve the approved source dimensions while revising this image; any later packaging canvas must pad/register the art without resizing it. Final runtime dimensions and transforms still require validation.
4. Store each bay polygon, seam, doorway/access point, obstacle and build-worker anchor in `warehouse_layout.lua`. Final vertex coordinates must come from the approved registered artwork, not the roughly drawn screenshot.
5. Show more environment on wider screens using larger view bounds at the established object scale. On narrow screens retain pan and player-controlled zoom. Do not secretly increase default mobile zoom to make the room appear to fit.
6. Keep screen-space GUI scaling independent of world framing. Validate touch coordinate conversion after this separation.

A fixed-aspect room cannot fill every aspect ratio, show everything, and keep objects the same pixel size simultaneously. Favor unchanged object scale and pan/expanded environment. The unpurchased bays intentionally remain black; they become useful screen-filling room only when bought.

## 3. Modular environment art contract

Author all variants against **one registered master**, not independent approximate room pictures. The corrected base's approved bottom is locked during the top-only revision; do not regenerate its bay shapes or short flat front edge. Each bay has its own oriented polygon; do not mirror baked lighting to make the opposite side.

Per bay, supply:

- locked black mask and removable threshold/edge trim;
- three completed options: floor, shelving, breakroom;
- four construction stage sets for each option;
- floor/background layer, foreground/occlusion layer, placement/walk mask, interaction anchors;
- one shared seam strip, at least 8 source pixels of matching texture underlap, and a placement metadata record.

Two bays × three room options × five visual states (four construction stages plus completed) gives **30 registered state sets**, before splitting into layers. Share foundation/framing assets where they genuinely match, but verify every final combination. Do not count an illustrative four-panel construction study as four ready-to-place sprites.

Seam requirements: same projection, tile pitch, grout phase, lighting, concrete color, floor height and outer wall thickness. Shared-edge source pixels should match; test for exposed alpha slivers at nearest-neighbor scale and mobile fractional scales. Temporary diagonal trim disappears when a completed floor connects to the base. No permanent wall, drop or dark stripe remains across an open-floor connection.

Storage option: shallow wall-mounted industrial racks with sufficient vehicle approach clearance, not a rack painted over the traversable floor. Separate rear frame and front beams so pallets can be drawn behind uprights. Preserve the user-approved first-person 2×5 design: ten **empty** openings, five across and two high, with no decorative pallets baked in. Layer extraction, slot registration, occlusion and runtime integration remain outstanding production steps.

Breakroom option: staff table/chairs, compact kitchenette/counter, lockers and rest area sized to the bay. Preserve the existing customer lounge; it is not the employee room. Deliver furniture and seating occlusion pieces separately. First release supplies the usable room and sit/rest interactions; do not imply a complete employee-needs simulation unless it is implemented as a separate feature.

## 4. Art and animation production list

| Family | Required production assets | First-pass strategy |
| --- | --- | --- |
| Base warehouse | Clean locked-base master, registered masks/foregrounds, dock/entrance compatibility | Preserve approved bottom; top-only taller architecture fills upper black gaps, then exact registration |
| Room options | Both oriented bays, floor/racks/breakroom, four construction states + finished | Start with bare-floor seam proof; derive other options from that master |
| Rack GUI | Empty 2×5 frontal rack, rear/front layers, ten slot anchors, hover/invalid overlays | Preserve user-approved design; separate/register layers and implement overlays in the game |
| Pallet views | Empty, raw paper, cut paper, printed stock, partially/fully wrapped, boxed and vendor stock as needed | Keep existing world pallets; author frontal variants and elevated world anchors |
| Forklift | All eight jack headings **NW, N, NE, E, SE, S, SW, W**, each unmanned and rabbit-manned; lowered/travel/upper forks, wheel motion, lift/lower, enter/exit | Initial four-diagonal study is incomplete; complete all eight registered headings, then layer mast/forks and carried pallet instead of baking every cargo combination |
| Jack operator | Rabbit gripping the existing jack handle in eight movement directions, matching planted idles | Eight walking phases per direction; hand anchors tied to jack handle |
| Mechanic | Reused eight-direction walk + idle; stage 1 concrete float, stage 2 framing hammer, stage 3 assembly drill, stage 4 finishing roller; carry-tool transitions | Preserve Mouse Frontier identity and approved stage/tool mapping; new work-loop sources require independent review |

Forklift layering recommendation: body/rear cage → seated driver → mast/forks/cargo → foreground cage. Unmanned/manned composites can be packed for performance, but remain derived from this shared geometry. Suppress only the actual forklift operator's walking avatar; retain player identity/nameplate and render all other workers normally. Rabbit-only driver art is the first supported design; non-rabbit selectable workers must not silently change species.

Fork heights are discrete gameplay levels (`ground`, `travel`, `upper`) with interpolated presentation. Separate load anchors for each direction/height keep the existing pallet's visible dimensions unchanged. Match the jack's full heading order: **NW, N, NE, E, SE, S, SW, W**. Both unmanned and rabbit-manned versions must cover every heading because steering, tools, mast details and lighting are asymmetric. The initial four-diagonal study does not satisfy this contract and must not be described as a complete direction set or animation atlas. Test rear views with cargo partly hidden by mast/cage.

For walking/pushing, use eight ordered poses: left contact, left down, right passing, right propulsion, right contact, right down, left passing, left propulsion. Advance gait from collision-resolved distance, not a timer; retain direction while idle and freeze feet when blocked. Pushing hands stay on the handle throughout. Forklift wheel motion follows actual travel; lift motion follows host lift progress, not character gait.

Character work sheets must preserve scale, contact anchor, costume, tool handedness and light direction. Working is a planted-foot action, not a bobbed idle. Match the mechanic's goggles, red scarf, tan shirt, brown overalls/tool belt and ringed tail. Do not resize the mechanic source directly at 0.30: apply the existing character-height normalization first.

Sprite-gait-overhaul gates: per-character motion JSON; contact-sheet and animated-loop inspection; no clipped/empty/duplicated-as-motion frames, matte/checker residue, anchor drift or left/right tool swaps. Only reviewed, normalized horizontal strips may move from staging to runtime.

## 5. Pallet racks: one inventory, two views

Add `pallet_storage.lua` and `screens/pallet_rack_screen.lua`. Both host and guest use the same screen and slot-layout data. Each slot shows the actual pallet appearance, job label, sheet count, cut/print state, wrapping and any spoil marker. A tap/click selects an actual shelf position; contextual Store/Retrieve buttons operate the nearby vehicle's load. This is not a generic bag inventory or a teleport menu.

Canonical ownership remains on the existing pallet:

```lua
pallet.location = "rack"
pallet.storage = { rackId = "front_left-rack", row = 2, column = 4 }
-- Floor stack alternative:
pallet.location = "stacked"
pallet.storage = { supportPalletId = "JOB-17-PALLET-01", level = 2 }
```

Derive slot occupancy from these references; never save another complete pallet inside a rack object. Preserve pallet ID, owning job/procurement order, remaining/finished/damaged sheets, artwork, paper geometry, completed print colors, drying deadlines and wrapped state.

Allowed new transitions: accessible floor/output ↔ jack/forklift; vehicle ↔ rack; forklift ↔ upper floor-stack pallet. Lower row uses row=1. Retrieve a lower pallet only if no stacked pallet rests on it. Reject stack cycles, mismatched/unsupported bases, occupied slots, wrong height, incomplete bays and insufficient approach clearance. Initial floor stacking is two high and restricted to catalog-marked stackable load types with compatible footprints; show the reason when a load is unsuitable.

The world renderer must draw stored pallets at rack-specific layer/height anchors, not as loose floor obstacles. The frontal rack renderer uses the same stable IDs with its own slot transforms and front-beam occlusion. Wrapped pallets remain wrapped when moved between views. A closed screen or lost connection cannot destroy or recreate stock.

## 6. Forklift behavior and safety

Add `forklift.lua`, reusing jack direction, movement, input and lease patterns without copying its singleton ownership into a second incompatible system. Refactor genuinely shared vehicle helpers only when tests protect jack behavior.

State machine: parked → mount → driving → align → lift/lower → transfer → driving/park. One operator and one carried pallet; a player cannot operate both vehicles. Driving requires forks at travel height; lifting/placing requires stationary alignment and clear space. Use a larger swept collision footprint and explicit turning/approach clearance. Touch players can tap a pallet/rack target to select it; confirmed transfer still requires the physical vehicle in range.

Host validates vehicle ownership, source pallet owner, location, rack/stack revision, target occupancy, distance, heading and fork height. Transfer is one atomic state change and one durable save; presentation must never briefly create a second pallet. Repeated requests replay their original result.

On disconnect or save/reload: stop motion, clear operator and input, retain cargo identity and fork position in a safe stationary suspended state. Do not automatically drop a load into an occupied cell or erase it. A new operator can safely lower or finish a validated transfer. Block dismount if no valid standing point exists.

Purchase through the existing CritterNet catalog/checkout path. Example developer-test prices only: open floor $2,500; storage $4,500; breakroom $3,500; forklift $6,500. Keep prices in one catalog; balance after playtesting against actual job margins. Shelf warning UI: `10 pallet spaces. Lower 5: pallet jack or forklift. Upper 5: forklift required.` These are neutral UI instructions, not character dialogue.

## 7. Construction and mechanic lifecycle

Use a separate `construction_worker.lua` queue; do not overwrite the existing `technicianVisit`, which is a single mouse/lizard machine-repair visit with hard-coded targets. Reuse its entrance conventions, not its four-second repair timer.

Purchase validates bay/catalog/cash, debits once, reserves a project ID and saves. Queue a `construction_notice` through the wall-phone system before dispatch. The phone currently holds one call; retain a durable pending notice and retry if a customer/supplier call occupies the line. Never replace an unrelated call.

Suggested appointment: arrival two game hours after the notice is presented. Answering confirms it; an unanswered completed ring produces an archived service notice and does not permanently block construction. Only announced appointments appear on the calendar; continue hiding unreceived client-email reply times. Keep new spoken raccoon lines pending user wording/approval; system UI can communicate appointment/project/stage without fabricated speech.

Worker path: exterior/front door → existing entry corridor → safe bay approach point → work anchor. Validate paths against moved machines, pallets and construction fences. Repath or report blocked access; never walk through scenery, stock or a locked bay. Reserve an approach aisle on purchase and show placement conflicts before accepting payment.

| Stage | Visible building state | Raccoon work tool/action | Duration and completion |
| --- | --- | --- | --- |
| 1 | Fenced foundation/slab work, wet concrete and delivered materials | **Concrete float**: spread and smooth the slab | 24 game hours from actual work start |
| 2 | Floor/wall framing, posts and rough services | **Hammer**: build the framing | Next 24 game hours |
| 3 | Option-specific structures and fixtures being assembled | **Drill**: fasten and assemble fixtures | Next 24 game hours |
| 4 | Final surface finishes, cleanup, checks and commissioning | **Roller**: apply finishing coats | Final 24 game hours; only then unlock room |

Four stage sprites are distinct from the finished module. All share the final footprint and seam registration. Preserve the stage/tool mapping exactly: **1 concrete float → 2 framing hammer → 3 assembly drill → 4 finishing roller**, one game day per stage. Generate genuine, distinct work loops for these tools rather than substituting a generic hammer or bobbed idle at every stage. Keep work-zone collision until commissioning ends; construction visuals never grant floor access early.

Persist absolute game-hour stage deadlines. Host processes crossed deadlines once, in order; saving/menus/low frame rates cannot duplicate progress or charges. No real-clock progress while the game is closed. Record blocked state and remaining work time if access genuinely prevents work. After final completion, publish the finished room/mask, send one completion notice, and route the mechanic out. Process a second queued bay only after the first visit is released.

## 8. Save and multiplayer contracts

Current save schema is v14; current multiplayer protocol is v16. Plan a new save migration and a protocol bump when these new state/action shapes land. Do not just attach unknown fields: current normalization/shared-field copying would discard them.

```lua
warehouse = {
  layoutVersion = 2, nextProjectId = 1,
  bays = { front_left = {status="locked"}, front_right = {status="locked"} },
  projects = {}, -- id, bayId, optionId, pricePaid, phase, stage, deadlines, notice/visit IDs
}
storage = { racks = {} } -- rack definitions/revisions; occupancy derived from pallet references
forklift = { owned=false, x=0, y=0, direction="northwest", forkHeight="ground" }
constructionVisits = {} -- project IDs, route/work/blocked state; no guest authority
```

Define migrated forklift parking from validated layout anchors, not these illustrative zero coordinates. Preserve every existing valid machine/pallet position. If the new footprint invalidates an old position, find a deterministic collision-safe location and report relocation; never discard stock. Existing saves start with both bays locked and no forklift, without cash deductions.

Extend `state.lua` defaults/shared fields, `save_schema.lua` normalization/validation/snapshots, `pallet_state.lua` ownership/reconcile logic, phone-kind validation and construction persistence together. Reject duplicate slot/pallet assignments and cyclic stacks on load.

Use `office_intent.lua` and `office_authority.lua` staged transactions for catalog purchases. Add bounded forklift/storage resources to `workshop_authority.lua` and strict actions in `net/protocol.lua`. Example intents: buy upgrade by bay/option ID; acquire vehicle; set fork level; pick/place by pallet and target slot; enter rack view; release safely. Never accept client price, elapsed build time, inventory count or world ownership claims.

Reliable shop updates carry durable projects and pallet placements. Compact runtime streams carry forklift pose/lift progress and mechanic motion. Preserve the 1,200-byte ordinary-packet ceiling and bounded 512KiB shop snapshot. Disconnect cleanup releases leases but preserves cargo/projects. Asset atlases and room textures are local package data, never network payloads.

## 9. Ordered implementation slices and acceptance

1. **Layout proof and art registration.** Preserve the already-approved base bottom and 2×5 frontal shelf design. Finish the base's top-only architectural revision and approve it plus one open-floor bay. Record seams/anchors/masks; test every existing entrance/dock/phone/customer foreground. Gate: no changed lower bay shapes, no apron/ramp, no object scaling, and seam-free floor at target screens.
2. **Durable upgrades + construction.** Catalog, migration, project queue, phone notice, four-day progression and raccoon entry/exit. Gate: locked masks until completion, safe save/reload at every stage boundary, busy/missed phone and blocked-route recovery.
3. **Lower-row storage.** Empty rack layers, frontal pallet variants, ten-slot screen with top-row forklift lock, jack transfer and world visibility. Gate: same pallet in both views, conservation across all lower columns, wrapped/printed/vendor stock preserved.
4. **Forklift and upper row.** Vehicle purchase, ownership, art states, alignment/lift/collision, upper transfers and two-high stacks. Gate: no teleport/duplicate cargo, no base removal under a stack, safe raised-load reconnect.
5. **Breakroom and complete art coverage.** Both bay orientations, all option stages, furniture/occlusion, jack-pushing animations, all reviewed vehicle/worker directions. Gate: no mirrored-lighting errors, clipped frames or sliding feet.
6. **End-to-end regression and packaging.** Extend guest cutting/printing journeys with rack/stack round-trips and construction recovery; then matching builds for later authorized device tests.

Tests to add:

- layout masks, seam pixels and source/world transforms; 4:3, 16:9, ultrawide and small Android landscape framing; before/after pixel-height checks;
- every bay/option/stage combination; foreground occlusion with all ten slots full;
- exact four × 24-hour transitions, saves just before/after each boundary, duplicate purchases/notifications/completion, queued second project;
- front-entrance route and busy/ignored phone without interfering with customers or existing technicians;
- lower row with jack; upper row denied without physical forklift; invalid height/alignment/occupied targets; two players racing for one slot;
- all stock types, damaged counts, print drying, wrapping and job accounting conserved through storage and shipment;
- driving/lifting controls on touch and keyboard, vehicle/pedestrian clearance, direction changes, operator avatar visibility;
- disconnect during lift, transfer or work stage; late/replayed intents; host/guest rack GUI equality; offline host-save reload;
- strict protocol shape/size/authority, schema migration and malformed occupancy/stack recovery;
- per-character motion audits and 1×/half-speed visual previews before integration.

## 10. Deliverables and honest status

The first generated images and exact generation prompts are indexed in [ART_STATUS.md](../assets/source/warehouse-expansion-v1/ART_STATUS.md) and [prompts.json](../assets/source/warehouse-expansion-v1/prompts.json). They remain source candidates, **not** seam-certified room modules, runtime-ready sprites or finished animation atlases. The corrected base bottom and the 2×5 first-person shelf design have visual approval; that approval does not imply layer extraction, anchor registration, masks, gameplay or runtime integration is complete. A top-remade base candidate now fills the upper voids and visually preserves the approved lower layout; it subtly repaints the lower raster and is not pixel-identical. Both unmanned and rabbit-manned eight-heading forklift source sheets are now present, superseding the incomplete four-diagonal study. The four construction-tool source sheets are present with explicit cleanup blockers in the art index. Existing gameplay asset paths and draw scales are unchanged in this planning/art pass.

The staged mechanic comes directly from the user-designated Mouse Frontier sibling project. Provenance is recorded without inventing a third-party license. The imagegen skill determines non-destructive source generation/staging; the sprite-gait-overhaul skill determines identity, direction, anchor and audit gates. Complete seam extraction, all module/stage variants, forklift animation states and jack-pushing strips remain production work after this first batch.

## 11. Earlier foundation handoff — superseded September 19, 2026

**Current update:** the first left-storage/forklift slice is enabled in normal play, with construction routing, four game-day stages and concrete/hammer/drill/paint work loops, shared shelf controls, floor cargo, host-authoritative upper-shelf transfers and two-high floor stacking. Taller upper walls now fill the top gaps without changing the lower registered warehouse or actor/equipment sizes. Protocol is **v19**, schema remains **v15**, and desktop/forced-mobile suites each pass **3,319 checks**. See [current build status](warehouse_build_status.md) for controls, verification and the explicit provisional-art boundary. The full lower-base/module remake and remaining room choices are not done. The text below records the earlier foundation-only stage and is no longer the current enablement status.

The first warehouse foundation is now implemented and tested; **new warehouse art and expansion gameplay are not enabled in normal play**. Sections 1–9 remain the design/acceptance specification, not a completion checklist. In particular, section 8 describes the old starting point: the implemented save schema is now **v15** and multiplayer protocol **v17**. The illustrative data in that section is not the exact shipped module schema. See [warehouse_build_status.md](warehouse_build_status.md) for the current contracts, integration gates and next work order.

Implemented foundation:

- Durable bay/forklift purchases, replay-safe receipts, one-worker construction queue, actual-arrival gates, four full 24-hour stages, blocked-work pauses, and rejection of forged early stage/completion records.
- A construction phone-service adapter plus neutral appointment/acknowledgement/missed-notice handling. It retries a busy phone and cannot complete construction without physical-worker callbacks; the normal app does not yet call this adapter or create the raccoon visit.
- Atomic single-owner lower/upper rack and two-high stack transfers; a shared first-person 2×5 rack presenter; forklift simulation and gated source-review lift presentation; a gated CritterNet purchase/confirmation screen and office-authority purchase handler.
- A tested host-side forklift floor-cargo adapter preserves the actual pallet and its work/material data on pickup, drop and movement. Realtime pose updates cannot create/revoke vehicle ownership or bypass another vehicle's seat lock. The adapter still needs its normal-world and network call sites.
- Defaults, save migration, shared durable state, raised-cargo recovery, malformed-source rejection, cross-vehicle seat guards, bounded transfer revisions and protection against consuming shelved/carried/supporting maintenance supplies. Genuine abstract-only starter kits remain usable.
- An isolated interactive forklift lift lab, separate from the normal shop/save flow, with eight-heading lower/mid/high capture coverage.

Latest verification: **3,003 passing checks / zero failures in desktop smoke and 3,003 / zero failures in forced-mobile smoke**. Reports: [desktop](../output/warehouse-build-desktop.rpt), [forced mobile](../output/warehouse-build-mobile.rpt). The isolated forklift lab successfully produced **24 refreshed direction/height captures**, confirmed by its [latest log](../output/warehouse-expansion-v1/forklift-lab-v3-stdout.log). The corrected north/south sources and preview framing were visually inspected; earlier capture sets are preserved separately. Capture success does not approve the source artwork, prove cargo occlusion, or replace connected-device/host–guest end-to-end tests.

Remaining integration order: registered base/bay geometry and masks → actual front-entrance construction worker and service bridge → gated catalog/phone/calendar wiring → lower-row rack transfers and both world/front views → forklift world controls/cargo/upper rows/stacks and host authority → complete module/animation coverage → end-to-end save/reconnect/framing tests → later authorized device testing and packaging. Keep the normal-play gates closed until the offered purchases have real, collision-safe, rendered results. Existing live warehouse paths and character/machine/pallet/jack scales are unchanged.
