# Household action production

This directory contains the directional props and matching character animation requested after the v1 prototype. Selected sweeping assets are now integrated; other studies remain as provenance. Source PNGs remain unchanged. `manifest.json` marks the actual runtime selections.

Requirements: eight actual directional views, frame-specific grip registration, consistent body scale/foot anchor, action-specific motion, authored hand/tool layering, and shared activity-clock timing. No generic work-loop or rotated single-view object counts as final coverage.

Current review:

- `broom-directions-study.png` had incorrect headings and insufficient side-view foreshortening. `broom-eight-directions.png` corrects those views. `broom-eight-directions-long-shaft.png` additionally gives both hands a practical grip area.
- `sweep-east-empty-hands.png` removes the first study's baked-in handle fragments. Its first four frames are the authored pull states. Playback will use 1,2,3,4,3,2 for a reversible pull/push loop; its bottom row is not used. A later attempted return-row edit was rejected and is documented in the manifest.
- Seven additional `sweep-*-study.png` sheets provide four pull poses each. Their actual dimensions are 1254x1254 (627-pixel cells), despite the requested 1024x1024. They require explicit frame registration and normalization, not assumptions about the requested dimensions.
- `sweep-north-rear.png` corrects the north study's diagonal body orientation. All new directions still require assembled grip, layering, loop and foot-contact review before runtime acceptance.
- `src/tests/home_action_art_review.lua` renders the staged east character and separate east broom in LÖVE for contact and animation inspection. It is enabled only by `PICTURE_SHOP_HOME_ART_REVIEW`; it does not change gameplay presentation.

Sweeping now uses `src/home_sweep_art.lua` and `src/home_sweep_registration.lua`: eight authored body/broom views, four poses with 1,2,3,4,3,2 playback at six phases per second, registered grips, planted feet and shared activity timing. The southeast/southwest/west grip edits and the northwest body separated from its coupled broom reference replace their earlier studies. North uses the corrected rear view. Front views redraw finger regions over the handle; rear views place the tool behind the body. All six colorways remain supported, and at most four directional body atlases remain resident.

All 32 grip contacts pass the review gate. The expanded sprite audit reports zero errors; sweep bounding-box warnings reflect the moving broom, with no clipping or baseline errors. Full desktop and forced-mobile suites each passed 8,625 checks, including all three guest observers. Other held-object/action families remain required work; sweeping does not complete the user's full animation request.
