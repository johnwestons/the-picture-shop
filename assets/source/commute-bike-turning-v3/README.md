# Regenerated 64-view motorcycle turntable

Selected runtime asset: `assets/commute/bike/mounted-upright-64-v2.png`.
All 64 upright views are newly authored. Layout remains 8 by 8, with 320 px
cells, anchor [160,260], runtime scale 0.46 and nominal 5.625 degree sectors.
Fixed third-person riding selects this atlas at all cruising speeds and through
banked turns. Follow and brief action poses retain their existing assets.

Built-in `image_gen.imagegen` generated the art with true transparency.
`generation-history.json` contains every exact selected prompt, reference,
generation pass and original tool-output path. `source-sheets.json` maps the
eight final source sheets to all 64 directions. The old accepted 64-view atlas
provided the eight `views-XX-template.png` references. The shared transparent
identity card fixes materials and proportions. Source images remain available
in their original generated locations; proportion drafts are also kept here
where subsequent edits reference them.

A full-set study lost detail, and generic quadrant studies changed directions;
those were rejected. Eight-view template edits preserve the accepted angle
sequence while providing more source detail. Groups 03 and 04 received helmet
proportion corrections, and group 07 was regenerated to remove background haze.
The final source objects are at least 267 px high, downsampled to 190–216 px in
the atlas. No new view is an interpolated, mirrored or alpha-blended sprite.
Physical art angles remain visually approximate, while runtime sector selection
is exact.

`tools/commute_lab/compile_bike_turning_quality.py` performs only transparent
gutter slicing, uniform per-cell resizing and registration. Helmet top targets
70 px. The tire-plane midpoint stays at [160,260], while the near tire extends
continuously with viewing angle. No axis stretching, repainting or morphing is
performed by the compiler. It writes staging, source rectangles/scales/hashes,
a contact sheet and before/after metrics, and fails its quality gates if the
new set regresses on worst or average size changes, silhouette steps or wrap.

The reviewed result halves average adjacent helmet-width change, from 1.875 px
to 0.9375 px. The largest change falls from 5 px to 3 px. Average second
difference, which exposes alternating size pulses, falls from 3.6875 to 1.6875.
Mean silhouette change falls from 0.10388 to 0.08609; the 95th percentile falls
from 0.18884 to 0.15438. These are sprite-image measurements.

Review evidence: `output/bike-turning-quality-review/acceptance.json`,
`size-and-transition-audit.json`, `native-64-views.png`,
`native-before-after.gif` and `native-regenerated-turn.gif`. Native LÖVE passes
320 checks and captures 128 sequential frames. Actual app runs pass 241 checks
each on desktop and simulated mobile, drawing all 64 directions once at alpha
1. The full isolated suite passes 10,056 checks. No physical phone was tested.
The walking auditor reports no image issues or warnings; its missing walking
direction/gait schema messages do not apply to vehicle yaw views.

Rebuild with `tools/commute_lab/compile_bike_turning_quality.py`. After reviewing
staging, copy its atlas to the selected runtime path. Run
`tools/commute_lab/review_bike_turning.ps1`, then the same runner with `-Runtime`,
`-Runtime -Mobile` and `-Runtime -Full`. Run
`tools/commute_lab/compare_bike_turning_quality.py` after native capture to
recreate the GIFs. The old native 64-view captures remain in
`output/bike-turning-64-review/` as the independent comparison baseline.
