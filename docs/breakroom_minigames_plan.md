# Break room games and purchasable objects

The completed break room has three independent purchases: an air hockey table, a freestanding wheeled basketball goal with a movable ball, and a **Critter Kombat** arcade cabinet. Each supports solo play and two players in the same shop. Purchases, sprites, interactions, host simulation, and network snapshots are implemented. The gameplay and layouts have not been run through the acceptance checklist below.

## Implemented controls and assets

Purchase the fixtures on the office computer's **Break Room Games** page after construction finishes. The game keeps each fixture and the basketball's last floor position in the shop save. Live matches reset when the shop is loaded.

| Game | Solo and shared play | Controls |
| --- | --- | --- |
| Air hockey | First to seven against AI or a second player | Interact with the table; move with WASD/arrows or drag a paddle with mouse/touch. Choose solo, invite, or join in the rink screen. |
| Basketball | Free shooting with a streak, or first-to-eleven contest | Interact with the ball to pick up. Q drops it on clear floor. Press Space to jump and release it near the apex to shoot. Interact at the goal to start or join a contest. Mobile offers Shoot and Drop actions. |
| Critter Kombat | Best of three rounds against AI or a second player | Interact with the cabinet. A/D or left/right move, Space jumps, J punches, K kicks, and L blocks. The GUI also has mouse/touch buttons. |

Runtime art lives in `assets/generated/breakroom-games-v1/`, with the cleared wall background at `assets/generated/shop-breakroom-games-v1.png`. Authoring sprites and atlases live in `assets/source/breakroom-minigames-v1/`; `tools/build_breakroom_games_assets.py` rebuilds the runtime images. Rabbit basketball actions use five authored direction atlases and mirror three westward views, matching the eight rendered directions of the walk rig. The arcade has separate 4×3 action atlases for the mouse and fox, plus a rail-yard backdrop and cabinet sprite.

## Room layout

The break room uses a 960 × 678 logical scene over a 1536 × 1024 background. Current fixture anchors are defined in `src/breakroom_games.lua`; the freestanding goal sits in the left foreground and the arcade faces left into the room.

| Object | Proposed anchor in logical room coordinates | Required clearance |
| --- | --- | --- |
| Basketball goal | Wheeled base at `(90, 500)`, rim at `(136, 330)` | Keep the floor approach at `(211, 475)` and a clear path for shots from the open room. |
| Air hockey table | Open central floor near `(475, 380)` | Leave a standing point at each short end and walking space around both sides. Do not overlap the shooting lane. |
| Critter Kombat cabinet | Right floor edge at `(887, 430)`, facing left | Keep access to the sofa, right chair, bookshelf, and return path. The cabinet has two control positions. |
| Basketball spawn | Clear left floor near `(240, 315)` | The ball can subsequently be picked up and placed on any valid floor spot in its current scene. |

Place fixtures as separate transparent world sprites. Register their floor contacts, collision footprints, interaction points, and foreground order independently of the painted room background. The goal's weighted base rests on the floor; draw its rim and net in front of a flying ball when the ball crosses the hoop plane. A purchase must fail cleanly if its reserved footprint is blocked by a movable object. Existing furniture cannot silently move under a player.

## Purchase and shared state

- Add a **Break room games** section to the existing computer warehouse catalog after a break room finishes construction. Offer each fixture once per completed break room bay. Suggested initial tuning prices are $1,800 for air hockey, $950 for the goal and ball, and $2,500 for the arcade cabinet; keep the authoritative price table in one catalog so balancing is simple.
- Use the existing host-owned purchase pattern: request ID, validated room ID, server-side price and cash debit, durable receipt, and replay-safe acknowledgement. Guests see the same catalog and can request a purchase; they cannot supply a price or award an item locally.
- Persist fixture ownership by bay. Persist each basketball as one bounded record with `id`, `sceneId`, floor `x/y`, `mode` (`placed`, `held`, `flight`), `holderPlayerId`, and a last valid floor position. A carried ball follows its holder across permitted scene transitions. Dropping checks the walk mask and obstacles and stores the exact accepted location. If a holder disconnects or a saved in-flight shot cannot resume, put the ball at its last safe floor location.
- Sessions, live puck/ball motion, scores, and temporary player locks are host-owned runtime state. End or safely cancel a session if a player leaves, disconnects, sells or loses access to the room, or opens an incompatible screen. Save purchased fixtures and the resting ball position; do not save an unfinished arcade or hockey match.

## Air hockey

Interacting with the table opens a top-down rink GUI. A player chooses **Solo vs AI** or **Invite player**. A second player can join from the same table; others may watch without controlling a paddle. First to seven goals wins. After each goal, pause for a short faceoff and reset the puck to center.

The host advances the puck, rails, goal sensors, and two paddles at a fixed simulation step. Players send bounded paddle targets or directional input; the host clamps each paddle to its half of the rink and publishes compact state snapshots. The AI follows the puck with a speed and reaction limit. On desktop, mouse or keyboard controls a paddle; touch drag and a virtual directional control cover mobile. The GUI draws score, exit/pause controls, and short control hints above the rink. The generated top-down rink and separate orange/teal striker and puck sheet supply the art.

## Basketball in the room scene

The basketball mini game runs in the room itself, with no dedicated game window or timing meter. **Interact** picks up the nearby ball. While held, the player uses dribble idle and dribble walk animations; the separate floor ball is hidden so it cannot be picked up twice. **Drop** places it at a valid nearby floor contact and saves that position.

**Shoot** turns the player toward the purchased goal and starts a jump shot. The player presses to gather and jumps, then releases the action near the apex. Release timing is measured against the animation's apex window; the apex gives the most accurate trajectory. Early or late release shifts the shot arc and lateral aim, with distance and movement adding predictable difficulty. The host creates the flying ball at the release frame, simulates rim/backboard contacts and bounce, awards a basket only on a downward crossing through the rim, then leaves the ball where it settles. A missed shot remains a physical ball. The existing HUD may show a short interaction hint and score; the jump, ball path, rim response, and sound provide shot feedback.

Solo mode is free shootaround with a local streak. Two players can start a shared first-to-eleven contest from the goal; there is still only one physical ball, and both players see the same score and possession. Joining a contest does not teleport the ball. The host validates pickup distance, holder identity, release time, scene, and hoop ownership. Shot results come from host simulation rather than a client's claimed score.

## Critter Kombat

Interacting with the cabinet opens a full GUI with a side-view 8-bit fighting arena. The first roster has a tinker fox and a cowboy mouse interpreted from the neighboring Mouse Frontier art. This is a new arcade treatment of those characters; the source references remain in the Mouse Frontier project. The first stage is a frontier rail yard with warm sunset light and a horizontally tracking camera.

Choose **Solo vs AI** or **Versus player**. A match is best of three 60-second rounds. Each fighter can move, jump, punch, kick, block, take a hit, and recover. Keep the first combat system small: readable startup/recovery windows, short hit stun, no weapons or gore, and no character upgrades that affect competitive balance. The host owns fighter positions, hit boxes, health, timers, and results. Clients send bounded button states; the GUI interpolates snapshots for display. Draw the exact title **Critter Kombat**, health bars, timer, controls, and results with the game's UI text layer rather than baking them into sprite pixels.

The final fox and mouse atlases each supply idle, walk, jump, punch, kick, block, hit, knockout, and victory poses. The rail-yard backdrop is separate from the fighters and tracks their midpoint subtly in the GUI.

## Original concept art

The nine initial concepts below remain in `assets/source/breakroom-minigames-v1/`. Additional direction and fighter atlases, the cleared room image, and sized runtime sprites were created during implementation.

| Source file | Purpose |
| --- | --- |
| `world-air-hockey-table-v1.png` | Room fixture and interaction target |
| `gui-air-hockey-rink-v1.png` | Top-down GUI playfield |
| `gui-air-hockey-pieces-atlas-v1.png` | Orange striker, teal striker, puck |
| `world-basketball-portable-{idle,rim,score}-v1.png` | Freestanding wheeled goal and aligned rim-hit / score feedback frames |
| `world-basketball-v1.png` | Movable ball and projectile |
| `player-rabbit-basketball-actions-atlas-v1.png` | Dribble idle, dribble walk, jump shot concepts |
| `world-critter-kombat-cabinet-v1.png` | Two-player room cabinet with blank marquee |
| `gui-critter-kombat-rail-yard-v1.png` | Pixel-art fighting stage |
| `gui-critter-kombat-fighters-atlas-v1.png` | Fox and mouse fighting poses |

The final reusable prompt set and reference roles are recorded in `assets/source/breakroom-minigames-v1/prompts.md`. The cabinet marquee is intentionally blank; **Critter Kombat** belongs in live text so spelling remains exact.

## Build order and acceptance

1. Prepare the source art: trim true-alpha sprites, slice atlases, align feet and ball contacts, create final world-scale strips, and review the freestanding goal, table, and left-facing cabinet composited over the room image.
2. Add fixture catalog entries, host purchase commands, receipts, save migration, room ownership, placement footprints, and multiplayer snapshots. Older saves load with no games purchased.
3. Implement the ball state and room rendering, then pickup, drop, dribble, shoot, rebound, and solo/two-player scoring. Confirm exact ball position and ownership after save/reload and disconnect.
4. Build the air hockey GUI and fixed-step host simulation; check solo AI, two-player joining, goals, score reset, close/reopen, keyboard, mouse, and touch controls.
5. Finish Critter Kombat animation coverage, then implement its GUI, AI, two-player match, hit boxes, round flow, and mobile controls.
6. Verify room walkability and access for every fixture combination, same-scene play for host and guest, joining and leaving sessions, blocked placements, duplicate purchase requests, and saved ball location. Package the source-derived runtime sprites for desktop and mobile.

The remaining acceptance work is a hands-on pass through all three games, both break room bays, solo and two-player sessions, saved ball positions, and the room's furniture clearance. Basketball uses a deterministic arc, scores on the downward crossing, and follows misses with a simplified rebound arc. The freestanding goal now reacts with aligned rim and swish frames when the shot outcome warrants them; detailed backboard collision geometry can be added during gameplay polish.
