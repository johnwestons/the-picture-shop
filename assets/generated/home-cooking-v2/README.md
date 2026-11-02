# Directional stove stirring

Integrated through `src/home_routine_pose.lua`, `src/home_cooking_art.lua` and `src/home_cooking_registration.lua`.

Eight independently authored views cover east, southeast, south, southwest, west, northwest, north and northeast. Each body sheet contains four stirring poses in a 2x2 grid of 627-square cells. The separate spoon and saucepan atlases contain eight views each. Explicit atlas regions preserve handles crossing nominal grid boundaries. Source PNG bytes are unchanged.

The character's planted foot and gripping hand are registered per frame. The selected spoon joins the hand to a small circular path inside the pan. The pan stays on the registered stovetop. Standing positions are checked against apartment and furniture collision; a small offset handles two wall-adjacent combinations. Character colors do not affect the props. The phase uses existing shared activity time, and the body cache holds at most four directional sheets.

The initial complete character/tool studies are retained as provenance. Only the eight `*-body.png` sheets and the two directional prop atlases are runtime assets. The built-in image generator produced every source; `manifest.json` records exact prompts, original paths, hashes, dimensions, alpha ranges and byte-preservation checks.

Review output lives in `output/home-action-review/`: `cook-all-directions.png`, `cook-stove-contact.png`, `cooking-registration.tsv`, `cooking-stove-placement.tsv`, and `cooking-audit/`. The cooking audit includes the existing base character animations and reports zero errors and three pre-existing walk/high-five warnings.

This completes the stove-stirring action, not preparation, eating, drinking, washing, laundry or the other household animation families in `docs/weekend_home_plan.md`. When custom furniture blocks every registered standing candidate, the existing work-pose fallback remains available rather than moving authoritative player coordinates into obstacles. Physical Android and real-device multiplayer acceptance are still pending.
