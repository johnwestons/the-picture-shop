# Character motion blueprint

The rabbit worker is the reference implementation for future player and NPC movement overhauls. Its reusable contract lives in `character-motion/rabbit-worker.json`, while the runtime implementation is split between character animation, player movement, and world rendering rather than embedded in character-specific drawing code.

## Reference result

- Eight movement sectors are available. East, northeast, southeast, north, and south are authored; westward views intentionally mirror the matching eastward strips.
- Every movement sector has a matching directional idle. When motion stops, the last nonzero movement vector is retained and selects the idle from the same sector and mirror decision, so the character never snaps back to a default facing.
- Every directional strip contains eight synchronized phases: contact, weight-down, passing, knee-up, opposite contact, opposite weight-down, opposite passing, and opposite knee-up.
- Frames advance from actual collision-resolved world distance. The reference cadence is 20 world pixels per frame.
- The 155-pixel/second base pace produces a nominal 129-millisecond pose and roughly 1.032-second full gait cycle.
- A smooth phase curve slows contact/loading to 0.96/0.94 of base speed and accelerates passing/knee-up to 1.04/1.06. Forward acceleration follows a separate 0.92/0.90/1.08/1.10 curve. The four values repeat for the opposite step.
- No-input and reversal braking are not gait-modulated. Input remains normalized, analog strength is preserved, collision movement is substepped, and blocked displacement does not advance the visible gait.

## Reuse workflow

Invoke the personal `$sprite-gait-overhaul` skill for a new character. It provides the art contract, JSON specification schema, automated strip auditor, contact-sheet and GIF generation, LÖVE integration pattern, and acceptance tests.

For each character:

1. Inventory existing source art, runtime actions, movement states, anchors, and asymmetries.
2. Create `character-motion/<character>.json` before generating or editing strips.
3. Produce direction studies, a two-pose directional idle sheet, then eight-phase gait strips only for approved views.
4. Normalize from immutable sources into staging; never repair runtime files destructively.
5. Run the reusable audit tool and inspect both labeled contact sheets and actual-speed GIFs.
6. Correct art until phase order, identity, transparency, scale, center, baseline, and loop seam are acceptable.
7. Register the reviewed assets and apply the shared distance clock and gait curve to that character's movement controller.
8. Add walk/idle direction pairing, retained-facing, cadence, speed-profile, acceleration, braking, collision, blocked-motion, and rendering regression tests.
9. Verify in the real game and on each supported form factor.

The JSON spec is the handoff between art and code. It records intentional mirroring, prevents silent direction gaps, makes frame/timing assumptions testable, and lets future audits reproduce the same result without rediscovering character-specific values.

## NPC migration order

Overhaul NPCs in small batches by shared body type or role. Start with the most frequently visible walking character, complete its art and runtime gate, then reuse the proven normalization and integration settings for close variants. Do not migrate every NPC simultaneously: one faulty reference strip otherwise propagates into the whole cast.

NPC pathing should feed actual post-collision displacement into the same animation-distance clock used by the player. Directional idle remains time-based but must resolve from the final movement sector. NPC state machines may still use separate sit, work, or machine-use actions; only locomotion needs the gait-distance contract. Characters that move on rails or are repositioned externally must either report their real displacement to the clock or explicitly disable gait speed modulation for that state.
