# Reviewed motorcycle atlas import

The generated 4×4 sheets are not a reliable direction map. The November 2026 audit found intermediate cells whose physical facing did not match their requested compass labels. The importer must not infer direction from row/column order or substitute a nearby subject for an empty cell.

The original eight views remain independent authored drawings. They are copied byte for byte into north, northeast, east, southeast, south, southwest, west, and northwest. The importer only fills the eight intermediate views after their actual facing has been visually checked across every pose being imported. It does not enable sixteen-view rendering by itself; runtime selection requires its own reviewed change.

Run from the repository root:

~~~text
node tools/commute_lab/prepare_bike_motion_atlases.mjs STAGE_ROOT RUNTIME_ROOT --review-manifest REVIEW.json [mounted-16.png ...]
~~~

The PowerShell wrapper requires the same file through -ReviewManifest. Old commands without review metadata fail before writing an atlas.

The review JSON requires:

- version: 1 and status: "approved_direction_review".
- review.reviewer: the reviewer name; review.evidence: a real contact sheet or review report file, resolved relative to the JSON.
- atlases: an object keyed by each requested output filename, such as mounted-16.png.
- Each atlas has sourceSha256 and originalSha256, binding review to the exact generated source PNG and existing eight-view PNG.
- Each atlas has sixteen frames. Every record names direction, observedDirection, source, cell, and reviewed: true. The observedDirection must describe the drawing that was inspected, not repeat the intended prompt without checking it.

Direction names, in output order, are:

~~~text
north, north-northeast, northeast, east-northeast,
east, east-southeast, southeast, south-southeast,
south, south-southwest, southwest, west-southwest,
west, west-northwest, northwest, north-northwest
~~~

Cell numbers are one-based, row-major. Original cardinal/diagonal records use source: "original" and the corresponding original cell 1–8. Intermediate records use source: "generated" and the explicitly reviewed generated cell 1–16. Records may appear in any JSON order; the importer selects by direction. A generated cell cannot supply two directions.

For example, a north-northeast record has this shape, but is not approval by itself:

~~~json
{
  "direction": "north-northeast",
  "observedDirection": "north-northeast",
  "source": "generated",
  "cell": 2,
  "reviewed": true
}
~~~

Do not manufacture a complete mapping for rejected artwork. If a required facing is absent, obtain and review a corrected source drawing first. Review all fourteen poses together: parked, mounted, tuck/transition, boost/transition, shift/transition, left/right turn and transitions, and impact/transition. Preserve exhaust/chain sides; do not mirror a bike to fill a missing view.

All requested metadata and source hashes are checked before preparation. Empty subjects, decode errors, and incomplete later atlases fail before any output is written. The exact hash-checked image bytes are used for preparation. This protects direction evidence against later source replacement; it does not automate semantic visual review or make disk write failures transactional.

Run the isolated importer checks with:

~~~text
node tools/commute_lab/test_prepare_bike_motion_atlases.mjs
~~~

The checks create synthetic colored-cell fixtures only under output/bike-direction-audit and never approve or rewrite production artwork. They cover explicit remapping, original-frame preservation, missing/false review evidence, changed source hashes, empty cells, and no partial outputs on validation/preparation failure.
