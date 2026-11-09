# Field technician motion

Status: **partially implemented** as part of the active animation-overhaul goal. Both technicians have reviewed directional idles, eight-phase north/south/east walks and realtime guest presentation. Five walk views per species and service art remain incomplete.

## Runtime changes

`src/technician.lua` records collision-resolved travel distance across every route segment, retains the last achieved direction, accelerates with the shared eight-phase gait profile, and clears stale motion when blocked. Idle clocks reset only after actual movement. Shop time acceleration continues to use a separate real-time movement clock. Legacy saves receive defaults for the new motion fields.

North, south and east walking use eight authored poses in the shared contact/loading/passing/propulsion order, following achieved distance. All views share the same 104-pixel stride cycle and keep the case in the anatomical right hand. East uses the canonical `walk` action; the others have directional suffixes. The other walk views retain the legacy presentation sampled from achieved travel, so blocked visits do not keep moving. Legacy service art also remains pending replacement.

Both species now have eight separately authored idle directions, each with a neutral pose and brief blink/settle. Western views are authored, preserving the case hand. The lizard source's two back-diagonal columns were reordered according to their visible camera view; no source pixels were mirrored. Stopped technicians use fixed foot anchors and a 64-world-pixel body height. The live character loader streams these strips through its existing bounded cache.

The user identified three ear-shaped lobes in a west-walk draft. Root confirmed that the original mouse west idle reference also had the extra rear gray ear. `mouse-west-idle-v2.png` removes it from both neutral and blink while preserving the small far ear and pink foreground ear. The builder excludes original atlas cells 4 and 12, registers the corrected pair, and pins its source hash. The reference extractor now uses that corrected neutral for future west art and preserves `mouse-west-original.png` for provenance. All other twenty-one runtime strips rebuild unchanged. The three-ear west walk drafts remain rejected and uninstalled; west walking itself is still pending.

The sprite lab labels missing walk art as **walk pending** rather than presenting idle drawings as valid walk frames. Approved walk/service actions use the `Technician.spritePose` seam.

`src/technician_pose.lua` carries a bounded nine-integer presentation array in realtime environment packets. An empty array clears a departed visit. Coordinates, direction, distance phase, clocks and movement state are validated before any environment state is applied. Host service/route authority stays in shared shop state. Session tick checks discard reordered poses.

`src/technician_replica.lua` interpolates guest position and distance phase together over one packet interval, including stride wrap. It adds no invented travel during packet gaps, keeps stopped facing and advances idle/service clocks in real time. The App updates it while guests have GUIs open. New shops and loads clear old realtime poses. Networked players need matching protocol builds.

## Art and rebuild

Immutable sources, exact generation prompts, engineering references and source hashes live in `assets/source/technician-motion-v2/`. The selected masters were generated with the built-in ImageGen tool. `source-manifest.json` distinguishes them from rejected gait drafts and records selected cells and image-reference roles. A pinned hash prevents silently changing an approved master.

Runtime idle assets are in `assets/generated/technician-motion-v2/field-mouse-technician/` and `assets/generated/technician-motion-v2/lizard-press-technician/`. Generated anchors, alpha bounds and registration paths live in `src/technician_art.lua`.

Run `python tools/build_technician_motion_v2.py` to stage sixteen idle strips and six north/south/east walks, labeled contacts, runtime/half-speed gait GIFs, correctly timed idle GIFs and per-character specifications under `output/animation-overhaul/technician-motion-v2/`. Inspect contacts and skill auditor reports before installing with `--apply`. `--apply-idles` remains an alias for the reviewed pack. No rejected master or rejected cell is installed.

The north gait combines a four-cell contact/loading master with separate right- and left-leg swing pairs. For the mouse's initial right-swing master, only its two top cells are selected; the incorrect lower pair is excluded. The lizard's final left-swing pair uses the approved mouse pair as a pose-transfer target while retaining lizard identity. These selections and source hashes are pinned in the manifest. One scale per master is aligned by the rigid head span before packing, preserving weight-shift differences without the shrinking caused by measuring lifted feet or differently shaded clothing.

The south gait uses four two-pose groups: left contacts, right contacts, right swing and left swing. Only the top row of `mouse-south-right-contacts.png` is approved; the lower row repeats a leading foot and is excluded. The lizard uses reviewed mouse poses as transfer targets with its own identity reference. Its first left-swing draft enlarged the case; `lizard-south-left-swing-v2.png` corrects the prop while retaining the leg poses. The original remains recorded as rejected. `phase_indices` in the source manifest records each selected cell's zero-based position in the final cycle.

The east gait also uses four two-pose groups. The initial eight-pose draft had a painted backdrop and unclear leg order, so it is excluded. The mouse's initial far-leg swing repeated the bent-back foot in both cells; `mouse-east-left-swing-v2.png` advances the second boot forward behind the supporting leg. Both initial contact groups produced excessive body-height changes after rigid head alignment. Their v2 masters keep the swing references' body proportions and distinct near/far arm positions, bringing the loop within the existing audit limits without changing thresholds. The lizard's four approved pairs transfer these reviewed poses while retaining its own identity. The previous twenty runtime strips rebuild byte-for-byte unchanged when east is added.

Review GIF delays distribute the format's 10 ms quantization across the loop, avoiding cumulative cadence drift from rounding every nominal 167 ms pose down to 160 ms. Runtime gait continues to follow achieved distance.

`tools/prepare_technician_motion_references.py` extracts view-specific reference cells and creates anatomical guide images. Guides are generation references, never runtime art.

## Evidence and remaining gate

- The sixteen idle strips and six north/south/east walks have no sprite-image audit findings. Each complete-character audit currently reports six real coverage errors: five missing directional walks and insufficient gait coverage. Both specifications explicitly record pending walk and service actions. The goal cannot treat these packs as complete.
- The regression suite covers retained direction through turns, full path distance, blocked/reopened routes, phase independence from wall time, acceleration/gait agreement, legacy defaults, zero movement time, eight authored idle directions, planted blink anchors and all eight distance phases of north/south/east walks. Capture movement uses a normalized 2D direction for position and stride, including interpolated guest poses.
- The October 27 full desktop and forced-mobile suites each pass 6,321 checks after the two-ear correction; reports are `output/animation-overhaul/ear-desktop-smoke.rpt` and `ear-mobile-smoke.rpt`. The focused animation suite passes 946 checks. The capture runner passes 356 scenes, including 64 technician neutral/blink world renders and 192 north/south/east-walk renders through host and interpolated guest poses. Phone captures emulate the landscape viewport on Windows. Selected east captures, corrected west neutral/blink captures and staged phase sheets were visually checked; GIF frame counts and nominal/half-speed delays were inspected separately. `output/animation-overhaul/mouse-anatomy/idle-head-audit-before.png` records the original reference defect.
- Realtime regressions cover wire round trips, malformed/sparse poses, packet-size bounds alongside four employees plus room doors and a truck, departure clearing, reordered packets, atomic environment rejection, stride-wrap interpolation, packet gaps, rounding at the loop seam and the actual guest multiplayer update while Options is open.

The rejected multi-view walk masters mixed camera views within rows and repeated a leading foot. Two single-view attempts and a correction still repeated leg phases or moved the case to the opposite hand. Keep these failures recorded; do not install them by relaxing audit thresholds or treating duplicate-looking standing/stride poses as new motion.

The successful art route isolates planted contact/loading pairs, then two swing poses for each moving leg. For remaining directions, keep one camera view fixed per source and verify both supporting/leading legs before assembly. Assemble eight reviewed authored phases, then inspect contacts and runtime-speed loops before replacing legacy walking. Service poses must keep a stable planted stance and readable tool contact.
