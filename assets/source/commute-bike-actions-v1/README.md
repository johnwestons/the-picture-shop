# Mounted motorcycle actions, 64 views

The unchanged approved neutral reference is `../commute-bike-turning-v3/`
and `../../commute/bike/mounted-upright-64-v2.png`, SHA-256
`e20a817500682b7124af1f904a3d5590df1eeaa8c36e65167ccad6c69890ab7b`.

Seven actions each have 64 independent midpoint and full-pose drawings:
acceleration, hard braking, physical left/right lean, aerodynamic tuck,
physical left-foot shift and impact brace. The 56 selected source sheets
contain 896 cells. Each 4-by-4 sheet repeats eight consecutive yaw views:
midpoints in the upper eight cells, full poses in the lower eight.

`production.json` selects the exact sheets. `selected-sources.json` records
their hashes and generation records. Each `.generation.json` preserves the
exact built-in ImageGen prompt, references and immutable original output path.
Original studies remain here for provenance; selection never interleaves the
old 16-view runtime poses. Lean revisions explicitly project the physical
turn side for every yaw. The rejected translucent `turnLeft-03-lateral-v2`
study is superseded by v3.

Rebuild using the bundled Python interpreter, from the project root:

1. `tools/commute_lab/compile_bike_actions.py`
2. `tools/commute_lab/register_bike_action_profiles.py`
3. Review `output/bike-actions-64-review/matched/` contact sheets.
4. `tools/commute_lab/publish_bike_actions.py --publish`
5. `tools/commute_lab/compile_bike_wheel_regions.py` for procedural tire-region metadata.
6. `tools/commute_lab/review_bike_actions.ps1`, then `-Runtime`,
   `-Runtime -Mobile` and `-Runtime -Full`.
7. `tools/commute_lab/review_bike_motion_fx.ps1`
8. `tools/commute_lab/preview_bike_actions.py`

Postprocessing is transparent slicing, detached-background cleanup, uniform
scaling, tire-plane translation and atlas packing. It never stretches axes,
mirrors bike anatomy or synthesizes in-between artwork. A robust periodic
upper-rig-envelope fit suppresses crop/scale jitter while retaining each
action's articulation. In deep tucks the upper envelope may be the shoulder
or back, so its width is a visual-review diagnostic rather than a helmet-size
measurement. Physical leaning and detailed anatomy also require visual review.

Runtime uses four 1280-pixel pages per state, unchanged 320-pixel cells and
a maximum of twelve resident action pages. Every draw selects one opaque
pose and direction. The native review captures all 960 mounted pose/direction
pairs through the production renderer; desktop and simulated mobile checks
also audit every action through `App.draw` in fixed and follow modes.

Verification on November 3, 2026: 460 native action checks and 49 native
procedural-effects checks passed. Final desktop/mobile effects runs each pass
99 checks with `-Runtime -Focus motorcycle-effects` (add `-Mobile` for touch).
Native scenes verify trail dust separately from the legacy test town.
The earlier action-only desktop and simulated mobile runs
passed 332 checks each and verified 1,920 draws
(15 mounted poses, 64 directions, fixed and follow), each with one opaque
sprite. The maximum resident art allocation was 111,411,200 bytes with twelve
action pages, compared with the previous 117,964,800-byte budget. The broader
commute focus passes 1,195 checks. These records establish
runtime verification; they do not record user approval of this new action art.

The full game suite currently stops at the separate cutter-screen cache check
`performance_machine_screen_reuses_textures_after_options`; see
`output/bike-actions-64-review/full-smoke.rpt`. The focused motorcycle runs
passed. A standalone probe confirms that the cutter pack exceeds its 32 MiB
inactive cache without loading motorcycle code. The walking auditor has two vehicle-inapplicable schema errors and
20 full-yaw range warnings, with no alpha, clipping or detached-component
findings. The vehicle acceptance report and reviewed contact sheets document
the relevant coverage, registration and physical-side checks.

The tire effect is a distance-driven material cue in the lower rubber regions,
with exact stopped/parked pixels, no sprite replacement and no extra bike draw.
The wheel-region builder changes metadata only. Its native review checks 120
pose/angle samples for unchanged alpha and confinement to the wheel regions.
Dust and exhaust are bounded local presentation particles; the stronger dust
appears on trails, and smoke originates at the physical right rear pipe.
Review captures and pixel acceptance records are under
`output/bike-motion-fx-review/`.
