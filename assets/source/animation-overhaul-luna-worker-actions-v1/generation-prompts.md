# Luna worker-action generation record

All listed generations and edits used the built-in ImageGen tool with a genuine transparent-background request. The output atlases remain in the source folder; selected atlases are identified individually in the adjacent manifest (tinker press v3 and ferret wrapper v1 for the priority pair). Input-image roles and SHA-256 hashes are in that manifest. The generation outputs were copied from the default generated-images location without removing those originals.

<a id="tinker-fox-work_press-generation"></a>
## Tinker fox work_press generation

Reference roles:
- Image 1: immutable 4×4 tinker fox worker-action atlas; existing work_press row supplies identity, outfit, style and view.
- Image 2: approved tinker fox motion atlas; identity, scale and planted-foot reference.
- Image 3: Heidelberg Windmill equipment layout only; not to appear in the character sprite.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose game sprite atlas source for a worker task animation
Input images: Image 1 is the immutable tinker-fox-worker action atlas; use its second row as the existing work_press costume, identity, camera view, scale, painterly outline, palette and lighting reference. Image 2 is an approved multi-direction motion atlas for identity and foot-baseline reference. Image 3 is the Heidelberg Windmill equipment reference only; do not draw any machine into the output.
Primary request: draw eight genuinely different consecutive full-body poses of the same tinker fox operating a Heidelberg Windmill printing press safely at the operator-side feeder/worktable. This is a side-facing action strip source atlas, character facing right toward the unseen machine surface. The worker's hands visibly meet a consistent imaginary safe worktable/control surface at about mid-torso height in the reach and contact poses; character only, with no paper, tools, props or machine drawn.
Subject: the exact tinker-fox-worker: orange fox, exactly two large upright fox ears, exactly two arms, exactly two legs, exactly one bushy tail, round brass goggles on the forehead, red neckerchief, tan sleeves, olive work clothes, brown gloves, boots and belt pouches. Preserve the same proportions and identity from Image 1; goggles remain goggles and must not become extra ears.
Pose order (4 columns × 2 rows, read left-to-right on top then left-to-right on bottom): 1 grounded ready stance, eyes toward press; 2 slight forward approach/weight shift with shoulders turning toward the feeder; 3 forward reach with the nearer gloved hand meeting the outer edge of the feed table, other hand steadying just beside it; 4 careful alignment/operation with both hands on the supported outer feed surface, clear of rollers and platen; 5 hands withdraw to the safe external controls at the same reach plane, one hand touches a control; 6 brief safe control hold/press while watching the press; 7 retract the hand and straighten with an easing shoulder/tail recovery; 8 balanced neutral ready stance, hands near waist. All eight silhouettes must visibly differ with no duplicate-as-motion frames. Feet stay planted in the same floor footprint throughout; only subtle body lean and arm/hand motion, no walking stride.
Composition: eight equal square cells in a clean 4×2 atlas; one complete character centered in each cell with generous clearance and the same size, head top, foot baseline, and ground-contact point in every cell. Keep the complete tail and ears inside every cell. The contact hands must land at a consistent forward-right contact point. No overlapping cells.
Style: match Image 1 closely: finely painted hand-crafted 2D game sprite, warm directional highlight from upper left, rich brown-black outline, detailed fabric/leather and soft fur, same contrast and color family. Maintain a stable right-facing 3/4 side view and consistent camera.
Constraints: genuine transparent background, preserve alpha; no checkerboard or matte; no text, labels, gridlines, borders, scenery, cast shadow, floor, extra characters, extra objects, paper, sparks, motion streaks, duplicated limbs or anatomy. Exactly 2 ears, 2 arms, 2 legs, 1 tail in every cell. Do not invent handling at moving rollers, impression cylinder or platen; only touch safe outer feeder/table surface and external controls.
</pre>

<a id="tinker-fox-work_press-cleanup"></a>
## Tinker fox work_press cleanup

Reference role: Image 1 is the staged v1 generated atlas and the exact edit target.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 action sprite atlas cleanup
Input images: Image 1 is the exact existing generated tinker fox work_press atlas and is the edit target.
Primary request: remove only the two short stray reddish motion marks above the extended paw in frame 6 (second row, second column). Leave that paw as a normal closed gloved hand contacting the imaginary external press control. Do not add sparks, effects, any extra objects or any new anatomy.
Constraints: preserve the exact eight poses, identity, two ears, two arms, two legs, one tail, outfit, colors, cell positions, character size, contact silhouettes, outlines, lighting and transparent background in every cell. Keep all other pixels and poses visually unchanged. No text, background, props, gridlines, matte or new effects.
</pre>

<a id="tinker-fox-work_press-refinement"></a>
## Tinker fox work_press refinement

Reference role: Image 1 is the staged v2 generated atlas and the exact edit target.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 tinker fox worker action atlas refinement
Input images: Image 1 is the current staged tinker fox work_press atlas and the exact edit target.
Primary request: refine only the two late-arm poses so the transition from feeder work to safe controls reads clearly. Frame 5 (second row, first column) is the withdrawal phase: bend the forward arm sharply and bring its gloved hand inward toward the chest, clearly away from the imaginary feed surface; the other hand lowers near the waist. Frame 6 (second row, second column) is a separate safe external-control hold: extend only the same forward arm partway toward a chest-height control point, with the gloved hand touching that point; keep the other hand lowered. Make the silhouettes of frames 5 and 6 clearly different. Feet stay planted.
Constraints: preserve frames 1–4 and 7–8, same worker identity, two upright fox ears, two arms, two legs, one bushy tail, scarf, goggles, outfit, colors, size, floor baseline, contact direction, outlines, lighting and transparent background. No machine or props, no paper, sparks, extra anatomy, text, borders or effects. No hand reaches into rollers or platen.
</pre>

<a id="ferret-work_wrapping-generation"></a>
## Ferret engineer work_wrapping generation

Reference roles:
- Image 1: immutable 4×4 ferret worker-action atlas; existing work_wrapping row supplies identity, outfit, left-facing style and view.
- Image 2: approved ferret motion atlas; identity, scale and foot-baseline reference.
- Image 3: skid-wrapper exterior control-post and turntable layout only; not to appear in the character sprite.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose game sprite atlas source for a worker task animation
Input images: Image 1 is the immutable ferret-engineer-worker action atlas; use its third row as the existing work_wrapping costume, identity, left-facing camera view, scale, painted outline, palette and lighting reference. Image 2 is an approved ferret motion atlas for exact identity and planted-foot scale. Image 3 is the skid-wrapper equipment reference only; use its exterior control-post location as context but do not draw any equipment in the output.
Primary request: draw eight genuinely distinct consecutive full-body poses of the same ferret engineer safely starting and monitoring the skid wrapper from beside its exterior control panel. Keep the source's left-facing side/three-quarter orientation, so the character reaches toward an unseen panel on image-left. This is character-only; no machine, pallet, film roll, wrap sheet or other prop is drawn.
Subject: the exact ferret-engineer-worker: gray-and-cream ferret, exactly two small rounded ferret ears partly beneath the brown goggle strap, exactly two arms, exactly two legs, exactly one long striped tail, blue-lensed brass goggles, dark green shirt, brown leather overalls/tool belt, brown work gloves and dark work boots. Preserve the source identity and clothing; the goggles are goggles, not extra ears.
Pose order (4 columns × 2 rows, read left-to-right on top then left-to-right on bottom): 1 planted ready stance, attentive gaze to the wrapper's exterior panel; 2 a small shoulder lean and forward reach toward the panel, both feet remain outside the turntable footprint; 3 near gloved hand meets the same exterior button area at chest height; 4 controlled single-hand button press, other hand kept relaxed at the side; 5 briefly hold contact while watching the wrapper from the safe standing position; 6 release the control and retract the hand; 7 settle upright with hands low, observing the machine cycle from a clear safe distance; 8 return to a quiet ready stance still facing the panel. Each cell has a visibly different torso, arm, hand or head posture, no duplicate-as-motion frames. No walking stride and no reaching into the rotating turntable or wrapping-film path.
Composition: eight equal square cells in a clean 4×2 atlas; one complete worker centered in each cell with generous clearance and matching scale, head-top and boot baseline. Keep both ears, full tail, hands and feet inside every cell. The hand contacts a consistent image-left point at chest height, then moves away from that same point.
Style: match Image 1 closely: finely painted hand-crafted 2D game sprite, soft fur texture, bold dark-brown outline, warm highlights from upper left, dark green and leather-brown work palette, consistent contrast and detail. Stable left-facing 3/4 side view and camera.
Constraints: genuine transparent background with alpha; no checkerboard or matte; no text or labels, no panel/grid/borders, scenery, cast shadow, extra characters, props, tools, buttons, film, plastic wrap, sparks, motion streaks or new effects. Exactly 2 ears, 2 arms, 2 legs and 1 tail in every drawing. The worker remains outside the turntable arc and touches only the exterior control panel.
</pre>

<a id="ferret-work_wrapping-refinement"></a>
## Ferret engineer work_wrapping refinement

Reference role: Image 1 is the staged v1 generated atlas and the exact edit target.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 game worker action sprite atlas cleanup
Input images: Image 1 is the existing ferret-engineer-worker work_wrapping atlas and the edit target.
Primary request: refine only two issues while retaining the same atlas and identity. First, make the late cycle poses clearly different: frame 5 (second row, first column) keeps one gloved hand on the same exterior panel point, with a small torso weight shift and gaze monitoring the wrapper; frame 6 (second row, second column) has visibly withdrawn that reaching hand to the chest with a bent elbow; frame 7 (second row, third column) stands upright with both arms lowered at the sides and watches the wrapper from a safe distance; frame 8 (second row, fourth column) is a distinct quiet ready pose with one hand resting at the belt and head turned back toward the panel. Preserve planted feet; no walking.
Second, ensure every drawing visibly contains exactly two small rounded ferret ears: one near ear at the back of the head and one smaller far ear partly peeking above the opposite side of the goggle strap. Keep these exactly two ears in all eight panels. Goggles are not ears.
Constraints: keep the first four action poses, all clothing, face, fur colors, goggles, scale, lighting, outline, tail, cell layout and transparent background unchanged. Keep each character anatomically correct with exactly 2 ears, 2 arms, 2 legs, 1 tail. Do not add hands, limbs, props, panel buttons, wrap film, roll, effects, borders or labels. The worker only contacts the wrapper's exterior control panel and stays clear of its turntable.
</pre>

<a id="ferret-work_wrapping-cleanup"></a>
## Ferret engineer work_wrapping cleanup

Reference role: Image 1 is the staged v2 generated atlas and the exact edit target.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 ferret worker action atlas cleanup
Input images: Image 1 is the current staged ferret work_wrapping atlas and the exact edit target.
Primary request: remove only the tiny detached black horizontal dash marks floating in the empty transparent margin immediately above the worker's head in cells 5, 6, 7 and 8 (bottom row, columns 1 through 4). These stray marks are not part of the character. Repaint those few pixels as fully transparent.
Constraints: preserve all eight worker poses, character identity and anatomy, exactly 2 ears (the profile far ear may be naturally occluded), 2 arms, 2 legs and 1 tail, clothing, goggles, colors, scale, hands, feet, all contact poses, cell alignment, outlines and transparent background. Change no character pixels. Do not add or remove any props or effects.
</pre>

<a id="ferret-work_wrapping-pixel-cleanup"></a>
## Ferret engineer work_wrapping pixel cleanup

Reference role: Image 1 is the staged v3 generated atlas and the exact edit target.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 character sprite atlas artifact cleanup
Input images: Image 1 is the current ferret-engineer-worker atlas and the exact edit target.
Primary request: in the bottom row only, erase the four short, detached, horizontal black strokes floating in the empty transparent area near the top of cells 5, 6, 7 and 8. Each stroke is above and to the left of its character's goggles/head outline, roughly 8 percent down from the top of its cell. These are stray marks, not fur or part of the ear/goggle silhouette. Make those pixels fully transparent.
Constraints: do not change or redraw any worker pixels, pose, head outline, ear outline, goggles, tail, hands, feet, outfit, color, scale or cell position. Keep the original 4×2 atlas and its genuine transparent background. Do not add objects, marks, labels, matte or effects.
</pre>

<a id="ferret-work_wrapping-profile-head-cleanup"></a>
## Ferret engineer work_wrapping profile head cleanup

Reference roles: Image 1 is the staged v4 generated atlas and edit target. Image 2 is the staged v1 atlas, used only as the clean profile-head identity reference.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 ferret worker sprite atlas cleanup
Input images: Image 1 is the current ferret work_wrapping atlas and the edit target. Image 2 is the earlier v1 atlas of the same worker; use only its clean profile head contour as the approved identity reference.
Primary request: in cells 5–8 only, clean the head-top silhouette to match Image 2's profile: the near rounded ferret ear is visible at the back of the head and the far ear is naturally hidden by the side view and goggle strap. Remove the detached short black dash above the head in each of these four cells. Treat each dash as an unwanted detached mark, never as an ear. Keep the head outline attached and clean.
Constraints: preserve all eight body poses, exact worker identity and anatomy (two ears total in the skull, 2 arms, 2 legs, 1 tail), all clothing, goggles, colors, hand positions, contact/recovery poses, scale, cell layout, outlines and transparent background. Do not add a second visible ear or any other ear-like shapes; do not change any non-head pixels. No effects, labels, props, lines, matte or extra characters.
</pre>

<a id="ferret-work_wrapping-regeneration"></a>
## Ferret engineer work_wrapping regeneration

Reference roles:
- Image 1: earlier clean ferret work_wrapping atlas; profile identity/head silhouette and style.
- Image 2: immutable ferret worker-action atlas; original work_wrapping clothing and pose style.
- Image 3: approved ferret motion atlas; scale and planted-foot baseline.
- Image 4: skid-wrapper exterior control-post/turntable layout only; not in the sprite.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose game sprite atlas source for a worker task animation
Input images: Image 1 is the earlier clean ferret work_wrapping action atlas; use only as the approved identity, outfit, profile head anatomy, painting style, scale and outline reference. Image 2 is the immutable 4×4 ferret action atlas; its third row is the original work_wrapping costume/pose reference. Image 3 is the approved ferret motion atlas for body scale and planted-foot baseline. Image 4 is the skid-wrapper layout only; do not draw equipment.
Primary request: create eight clearly different full-body poses of the same ferret engineer starting and monitoring a skid wrapper from the safe exterior control panel. Preserve the exact left-facing profile/three-quarter view and original head silhouette from Image 1: two ears are present anatomically, with the far-side ear naturally hidden behind the skull and goggle strap from this side view; keep only the same single near-side rounded ear visible. No detached marks or ear shapes above the head. The character reaches image-left toward an unseen exterior button area; character only.
Subject: same gray-and-cream ferret, two arms, two legs, one striped tail, blue-lensed brass goggles, dark green shirt, brown leather overalls/tool belt, brown work gloves and dark work boots. Keep all identity details, goggles are goggles and not ears.
Pose order in a clean 4 columns × 2 rows atlas, read left-to-right across the top then bottom: 1 balanced ready stance with one hand at belt; 2 small forward shoulder lean, leading forearm raised but paw still short of the panel; 3 reach fully to the exterior control and visibly touch the same chest-height point; 4 controlled button press with a small wrist angle change while maintaining safe contact; 5 brief hold at the same contact point while the head turns to monitor the wrapper; 6 release and clearly fold the reaching elbow, drawing the paw back toward the chest; 7 stand upright with both arms lowered while observing from outside the turntable arc; 8 reset ready stance with one hand at the tool belt and gaze back toward the panel, distinct from frame 1. Every pose must be visibly distinct with no duplicate-as-motion frames.
Composition: one complete worker centered in each of eight equal square cells, matching scale and consistent head-top, foot baseline and ground anchor. Keep the full tail, ears, gloves and boots inside all cells. Feet remain planted in one floor footprint; no walk stride.
Style: match Image 1 closely, finely painted hand-crafted 2D game sprite, soft fur detail, rich brown-black outline, warm upper-left light, dark-green shirt and leather-brown overalls, stable side view.
Constraints: genuine transparent background and alpha, no checkerboard, background matte, panel, machine, pallet, film, wrap sheet, tools, buttons, sparks, motion marks, labels, text, borders, shadows, extra objects or characters. Exactly two ears total, two arms, two legs and one tail per character. The worker contacts only the exterior control panel and stays clear of turntable and film path. Do not draw a detached far ear; preserve the profile head contour in Image 1.
</pre>

<a id="ferret-work_wrapping-pose-edit"></a>
## Ferret engineer work_wrapping pose edit

Reference role: Image 1 is the clean original work_wrapping atlas and exact edit target.

Exact prompt:

<pre>
Use case: precise-object-edit
Asset type: transparent 4-by-2 ferret worker action sprite atlas
Input images: Image 1 is the clean original ferret work_wrapping atlas and exact edit target. Keep its head contour as the approved profile identity reference.
Primary request: change only the lower-row body poses in cells 5–8, preserving the established profile and clear spacing. Frame 5 remains at the panel with one hand contacting the same exterior control point, but turn the head to monitor the wrapper and shift the torso subtly. Frame 6 releases the panel and folds that arm clearly back toward the chest. Frame 7 is a distinct upright safe-observer pose with both hands down and feet outside the turntable arc. Frame 8 returns to ready with one hand at the belt and gaze toward the panel. Keep each entire character comfortably inside its square cell with transparent margin, especially the reaching hand in cell 5.
Constraints: preserve cells 1–4 exactly, same ferret face/head contour, exactly two ears anatomically (profile far ear naturally occluded; one near ear visible), two arms, two legs, one striped tail, outfit, goggles, palette, outline, scale, foot baseline, cell layout and transparent background. Do not add detached marks, extra ears, limbs, prop, panel, film or machine. Do not crop or clip any body part. No walking, text or effects.
</pre>

<a id="ferret-work_wrapping-margin-generation"></a>
## Ferret engineer work_wrapping margin generation

Reference roles:
- Image 1: clean original ferret work_wrapping atlas; profile identity, head and art style.
- Image 2: immutable ferret worker-action atlas; work_wrapping costume.
- Image 3: approved ferret motion atlas; scale and planted feet.
- Image 4: skid-wrapper layout only; external panel location.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose 2D game sprite atlas for a worker action
Input images: Image 1 is the clean first ferret work_wrapping atlas; identity, outfit, clean profile head and art style reference. Image 2 is the immutable ferret worker-action atlas, row 3 work_wrapping costume reference. Image 3 is the approved ferret motion atlas, body scale and ground-contact reference. Image 4 is the skid wrapper equipment reference only, showing the exterior panel location.
Primary request: create eight distinct full-body poses of the same ferret engineer operating only the skid wrapper's safe exterior control panel. Maintain the left-facing side/three-quarter view from Image 1; the worker reaches toward an unseen panel on image-left. No equipment or props drawn.
Subject: same gray-and-cream ferret, exactly two ears anatomically (profile view shows the same single near-side rounded ear; far ear is naturally hidden by the skull and goggle strap), two arms, two legs, one striped tail, brass blue-lensed goggles, dark-green shirt, brown leather overalls/tool belt, brown gloves and dark work boots. Preserve the approved head contour from Image 1; no detached or floating marks above it.
Pose order: 4 columns × 2 rows, row-major. 1 ready facing panel, one hand at belt. 2 shoulder lean and leading arm reaches partway, paw remains short of the panel. 3 full reach with paw contacting one chest-height exterior control point. 4 small wrist press at that same point. 5 hold contact while glancing toward the wrapper. 6 release and fold the leading arm to the chest. 7 stand clear with both arms down and watch the cycle. 8 reset to a distinct ready pose, one hand at belt, gaze at panel. Feet stay planted and every pose's silhouette differs.
Composition: eight square cells. In EVERY cell, keep the complete character between 64% and 78% of the cell width including the reaching paw and tail, and about 72% of cell height; leave at least 12% transparent padding on both left and right and at top. Position the torso slightly right of the cell center to make safe room for the leftward reach. Keep hand contact inside the cell, not at the border. Consistent character scale, head height, foot baseline and anchor. No overlap between cells.
Style: match Image 1: painted hand-crafted 2D game sprite, soft fur, deep brown outline, warm upper-left light, same palette and contrast.
Constraints: genuine transparent background; no checkerboard, matte, text, labels, panel, machine, pallet, film, plastic wrap, tools, buttons, sparks, motion marks, extra shapes, shadow, scenery or extra characters. No clipped body parts. Exactly 2 ears total, 2 arms, 2 legs and 1 tail in every cell. The worker touches only the exterior control panel, staying outside the turntable arc and film path.
</pre>

<a id="tinker-fox-work_cutter-generation"></a>
## Tinker fox work_cutter generation

Reference roles:
- Image 1: immutable tinker worker-action atlas; identity and work_cutter row.
- Image 2: approved tinker motion atlas; scale and foot baseline.
- Image 3: Polar 115 equipment layout only; safe feed edge and control placement.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose 2D game sprite atlas for a worker task animation
Input images: Image 1 is the tinker-fox-worker action atlas; its first row is the identity, outfit and existing cutter-task reference. Image 2 is the approved tinker fox motion atlas for scale, style and foot baseline. Image 3 is the Polar 115 cutter equipment layout only; do not include a machine in the output.
Primary request: create eight distinct full-body poses of the same tinker fox operating a Polar 115 paper cutter from its safe operator side, facing right toward the unseen machine. Show hands meeting an implied supported outer feed surface and then the external safety control area; character only.
Subject: exact orange fox worker, two large upright ears, two arms, two legs, one bushy tail, brass forehead goggles, red neckerchief, tan sleeves, olive work clothes, brown gloves, boots and belt pouches. Preserve Image 1 identity, proportions, palette, painterly outline and warm upper-left light. Goggles are goggles, never additional ears.
Pose order in a clean 4×2 atlas, row-major: 1 ready stance facing the cutter; 2 small forward lean toward the safe outside edge of the feed table; 3 reach and contact the outer supported paper-stack area, clear of the blade line; 4 careful alignment at that same outer edge with both hands still outside the guarded cutting area; 5 withdraw hands completely from the feed surface and reach toward the external safety controls; 6 place both hands on the two separated external safety buttons together to initiate the cut; 7 release and retract both hands away from the buttons; 8 settle back into a ready stance. Each pose has a visibly different silhouette. Keep feet planted; no walking.
Composition: one complete character per equal square cell with consistent size, head top and foot baseline. Keep tail, ears, hands and boots entirely inside each cell with generous transparent margins. All hand contacts stay within their cell.
Constraints: genuine transparent background with alpha; no checkerboard or matte; no machine, paper stack, tools, buttons, control panels, labels or other props are drawn. No sparks, motion streaks, scenery or shadows. Exactly 2 ears, 2 arms, 2 legs, 1 tail. Never reach toward or beneath the blade, clamps, or black cutting line; touch only the safe outside table edge and external controls.
</pre>

<a id="tinker-fox-work_wrapping-generation"></a>
## Tinker fox work_wrapping generation

Reference roles:
- Image 1: immutable tinker worker-action atlas; identity and work_wrapping row.
- Image 2: approved tinker motion atlas; scale and baseline.
- Image 3: skid-wrapper panel and turntable layout only.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose 2D game sprite atlas for a worker task animation
Input images: Image 1 is the tinker-fox-worker action atlas; its third row supplies identity, outfit and original work_wrapping reference. Image 2 is the approved tinker fox motion atlas for scale, style and baseline. Image 3 is the skid-wrapper exterior-control and turntable reference only; do not draw equipment.
Primary request: create eight distinct full-body poses of the exact tinker fox worker starting and monitoring the skid wrapper from beside its exterior control post. Face right toward an unseen control panel. The gloved hand contacts only the external panel area; the worker stays clear of the turntable and film path. Character only, with no pallet or wrapping props.
Subject: orange fox with exactly two large upright ears, two arms, two legs, one bushy tail, brass forehead goggles, red neckerchief, tan sleeves, olive work clothes, brown gloves, boots and belt pouches. Preserve Image 1 face, anatomy, palette, detail, outline, scale and warm upper-left light. Goggles are goggles and never extra ears.
Pose order in a 4×2 row-major atlas: 1 ready facing the control post; 2 lean forward and raise leading arm toward panel; 3 paw contacts one exterior control at chest height; 4 make a single controlled press at the same point; 5 brief hold while turning gaze toward the rotating wrapper; 6 release and draw the hand back to the chest; 7 stand upright with both arms lowered, watching from outside the turntable arc; 8 recover to a ready stance with one hand at the belt. Each pose has a visibly distinct silhouette; feet remain planted.
Composition: one complete worker per equal square cell, consistent size and foot baseline, full ears, tail, hands and boots visible. Keep every part comfortably inside each cell with clear transparent margins; no cell overlap.
Style: match Image 1, hand-painted 2D game sprite, soft fur and cloth detail, rich dark-brown outline, warm upper-left light.
Constraints: genuine transparent background and alpha; no checkerboard, matte, machine, panel, pallet, film, plastic wrap, tools, button, effect, motion mark, labels, text, shadows, scenery or extra character. Exactly 2 ears, 2 arms, 2 legs, 1 tail per pose. Never touch the turning platform or wrap-film path.
</pre>

<a id="ferret-work_cutter-generation"></a>
## Ferret engineer work_cutter generation

Reference roles:
- Image 1: immutable ferret worker-action atlas; identity and work_cutter row.
- Image 2: approved ferret motion atlas; scale, profile and foot baseline.
- Image 3: Polar 115 layout only; safe feed edge and controls.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose 2D game sprite atlas for a worker task animation
Input images: Image 1 is the ferret-engineer-worker action atlas; its first row is the work_cutter identity, outfit and pose reference. Image 2 is the approved ferret motion atlas for scale, profile and planted-foot baseline. Image 3 is the Polar 115 cutter machine layout only; do not draw the machine.
Primary request: draw eight different full-body poses of the same ferret engineer safely working at the Polar 115 cutter from its operator side, facing left toward the unseen machine. Show only the worker; hand contacts meet the implied outer feed-table edge and then the separated external safety controls.
Subject: exact gray-and-cream ferret, two ears anatomically (one near rounded ear visible in this profile, far ear hidden by the skull/goggle strap), two arms, two legs, one striped tail, blue-lensed brass goggles, dark-green shirt, brown leather overalls/tool belt, brown gloves and dark work boots. Preserve Image 1 identity, scale, palette, outline and lighting.
Pose order in a 4×2 row-major atlas: 1 stable ready stance; 2 small lean/reach toward the outside edge of the supported feed table; 3 near gloved hand contacts that outer table edge, away from the blade; 4 align from that same safe edge, both hands clear of the guarded cutting area; 5 withdraw both hands and reach toward the external safety buttons; 6 press both separated safety controls at the same time with arms safely outside the cutter; 7 release and retract hands; 8 return to a neutral ready stance. Each silhouette differs; no walking.
Composition: one complete worker in each equal square cell, with matching scale, head height, ground baseline and clear transparent margins around ears, tail, hands and boots. All body parts stay within the cell.
Style: match Image 1's hand-painted 2D game sprite, soft fur, dark-brown outline, warm upper-left light, green and leather-brown clothing.
Constraints: genuine transparent background with alpha. No checkerboard, matte, machine, paper, props, tools, panel controls, buttons, text, border, scenery, shadow, sparks, motion marks or extra characters. Exactly 2 ears total, 2 arms, 2 legs, 1 tail. Never reach under the blade, clamps, or cutting line; touch only the outer supported surface and external safety controls.
</pre>

<a id="ferret-work_press-generation"></a>
## Ferret engineer work_press generation

Reference roles:
- Image 1: immutable ferret worker-action atlas; identity and work_press row.
- Image 2: approved ferret motion atlas; scale, profile and foot baseline.
- Image 3: Heidelberg Windmill equipment layout only; safe feeder and control layout.

Exact prompt:

<pre>
Use case: stylized-concept
Asset type: transparent 8-pose 2D game sprite atlas for a worker task animation
Input images: Image 1 is the ferret-engineer-worker action atlas; its second row supplies the existing work_press identity, outfit and style. Image 2 is the approved ferret motion atlas for scale, profile and foot baseline. Image 3 is the Heidelberg Windmill equipment-layout reference only; do not draw any machine.
Primary request: create eight distinct full-body poses of the same ferret engineer working at a Heidelberg Windmill printing press from the safe operator side. Preserve the left-facing side/three-quarter view so the ferret reaches toward an unseen supported feeder/worktable on image-left. The worker's hands contact only the safe outer paper-support surface or external controls; character only.
Subject: the same gray-and-cream ferret with exactly two ears anatomically (one near rounded ear visible in profile, far ear naturally occluded by skull and goggles), two arms, two legs, one striped tail, blue-lensed brass goggles, dark-green shirt, brown leather overalls/tool belt, gloves and dark work boots. Preserve Image 1 identity, scale, palette, painted outline and warm upper-left light.
Pose order in a 4×2 row-major atlas: 1 planted ready stance looking to the press; 2 small lean toward the outer feeder; 3 reach with the near glove contacting the same supported outer table edge, far from rollers; 4 use both hands to align/steady at the safe table edge, clear of rollers, nip points and platen; 5 retract hands to the external controls; 6 controlled one-hand press/hold on a safe exterior control while watching the press; 7 release and lower the hand, recovering upright; 8 return to a balanced ready pose. Make all eight poses visibly distinct, feet planted, no walking.
Composition: one whole character per equal square cell; same size, head height, foot baseline and ground-contact point in every cell. Keep ears, full tail, both hands and boots inside each cell with generous transparent padding.
Style: match Image 1 closely: painted hand-crafted 2D game sprite, soft fur detail, deep brown outline, warm upper-left highlights, green and leather-brown outfit.
Constraints: genuine transparent background and alpha; no checkerboard, matte, machine, paper, tools, props, labels, panel, extra buttons, scenery, shadow, sparks, motion marks, text, border or extra characters. Exactly two ears total, 2 arms, 2 legs, 1 tail. Never reach into moving rollers, nip points, impression cylinder or platen; touch only the outside supported table and external controls.
</pre>

<a id="tinker-fox-work_cutter-control-edit"></a>
## Tinker fox work_cutter control edit

The same exact prompt was used twice. Image 1 was the v1 cutter atlas edit target; Image 2 was the immutable tinker action atlas for exact identity, costume and right-facing style; Image 3 was the approved motion atlas for scale and planted feet; Image 4 was Polar 115 layout context for safe feed-table and external controls only. Attempt 1 omitted the ImageGen transparent-background flag and returned opaque checkerboard; attempt 2 set `transparent_background=true` and returned the selected transparent v3.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact edit target: the current tinker-fox-worker work_cutter 4-by-2 action atlas. Image 2 is the immutable worker action atlas for exact fox identity, cutter clothing, painterly style and right-facing view. Image 3 is the approved motion atlas for body scale and planted-foot baseline. Image 4 is the Polar 115 layout for safe operator-side feed-table and external-control placement only; do not draw the machine. Edit only frame 5 (second row, first column) and frame 6 (second row, second column) to make the two-hand control sequence clear and safe. Frame 5 withdraws both arms from the feed edge and bends both elbows into a level, waist-height reach toward the external controls; show two separate attached gloved hands at the same height, torso upright, feet planted. Frame 6 is a distinct simultaneous two-hand control hold: both hands contact two separate external safety controls at exactly the same low waist-height plane, with level forearms, visible wrists and evenly bent elbows. The hands are clearly separated and each connects to one of exactly two arms. No raised arm, no one-hand-only hold, no crossed arms. Keep frames 1–4, 7–8 unchanged. Preserve the exact orange fox, exactly two large upright ears, two arms, two legs, one bushy tail, goggles, red scarf, tan sleeves, olive workwear, gloves, proportions, palette, warm upper-left lighting, dark outline and camera. The fox faces right, reaches toward one consistent unseen operator-side surface, and keeps its planted feet in the same floor footprint. Character only: no cutter, buttons, paper, tools, panels, props, extra objects, text, gridlines, borders or effects. Never reach toward or under the blade, clamps or cutting line. Genuine transparent background; no checkerboard or matte. Keep the same 4-column by 2-row cell layout and dimensions as Image 1. All eight poses must remain separate, full-body, and anatomically correct.
</pre>

Output review:
- Attempt 1: `assets/source/animation-overhaul-luna-worker-actions-v1/tinker-fox-worker-work_cutter-v2-rejected-opaque-checker.png`, SHA-256 `1FB353094C148B6B75EAC0A90FEB5D06CA68FBF409374D784689CFCFB2466385`; alpha extrema were 255–255, so it is rejected.
- Attempt 2: `assets/source/animation-overhaul-luna-worker-actions-v1/tinker-fox-worker-work_cutter-v3-generated.png`, SHA-256 `AE2583B8AB481B2CA3809144A91BC541B32DF7F4A4748F83EC93651B6B326681`; selected source candidate. Frames 5–6 now show both hands at one shared low control plane. Connected alpha QA reports no border contact.

<a id="ferret-work_wrapping-edge-repair"></a>
## Ferret engineer work_wrapping edge repair

Image 1 was the v1 edit target, Image 2 the immutable action atlas for identity/costume/left-facing style, Image 3 the approved motion atlas for body scale/feet, and Image 4 the wrapper layout for equipment context only. `transparent_background=true` was set.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact edit target: the current ferret-engineer-worker work_wrapping action atlas, 4 columns by 2 rows. Image 2 is the immutable identity and costume reference; Image 3 is the approved scale and planted-foot reference; Image 4 is equipment-placement context only. Correct actual cell-edge clipping while preserving the eight poses. In cells 1, 2 and 3 (top row columns 1, 2, 3), translate the entire existing worker up within the cell without changing its size or anatomy so the complete boot soles have at least 16 source pixels of transparent clearance below; in cell 3 also translate the whole worker slightly left so the entire striped tail has at least 16 transparent pixels to the right. Keep each figure's head and torso at the same visual scale as the neighboring cells and keep the same safe ground-contact pose. In cell 4, erase only the tiny detached residue on the far-left cell edge, preserving the intact worker. In cells 5, 6, 7 and 8 (bottom row), erase only the small detached stray marks on the top cell border; leave the full character pixels unchanged. Do not change the hand-contact phases, pose order, face, outfit, palette, outline or lighting. Exactly two ferret ears anatomically: show the near ear in the strict side profile and let the far ear remain naturally occluded by the skull and goggles; do not add a second visible ear or ear-like marks. Exactly two arms, two legs, one long striped tail, blue-lensed brass goggles, dark-green shirt, brown leather overalls/tool belt, brown gloves, dark boots. Keep all hands attached to the arms and the same side view reaching image-left toward the unseen exterior wrapper control panel. Stay clear of the turntable and film path. No machine, buttons, props, film, text, borders, labels, checkerboard or matte. Genuine transparent background and alpha. Retain exact 4-by-2 arrangement, cell divisions and dimensions of Image 1; do not resize or crop the canvas.
</pre>

Output review: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_wrapping-v10-margin-corrected-generated.png`, SHA-256 `0B866802120645C3FD79ADFFC2087B5D4F1AA9C89850DB9C5A104346A0E2CFCA`. This removed the row-edge clipping but frame 6 still had 8 connected body pixels on the right edge, so it was not selected.

<a id="ferret-work_wrapping-frame6-margin-refine"></a>
## Ferret engineer work_wrapping frame 6 margin refine

Image 1 was the v10 edit target; Images 2 and 3 were the immutable action identity/costume and approved motion-scale references. `transparent_background=true` was set.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact ferret work_wrapping edit target; images 2 and 3 are identity/costume and motion-scale references. Change only cell 6 (bottom row, second column). Translate the entire existing ferret pose slightly left inside that same cell, with no size change, until the tail tip and all other parts have at least 16 transparent source pixels of right-side clearance. Do not crop, redraw, shorten or alter the tail. Preserve the same frame-6 release-and-retract pose, exact head/torso scale, limb connections, clothing, colors, lighting, linework, feet and ground baseline; keep both feet planted. Do not change any other cell. Maintain the gray-and-cream side-facing ferret with exactly two ears anatomically (near ear visible, far ear occluded), two arms, two legs and one striped tail. No detached marks, props, background, panel, checkerboard or matte. Genuine transparent alpha. Retain the exact 4×2 arrangement and 1774×887 canvas.
</pre>

Output review: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_wrapping-v11-margin-cleanup-generated.png`, SHA-256 `90FA6D6DD20E6E112C942E7F582C5D90E2DAB8724D3799F850CF5719E5D60964`. This is the selected candidate; connected alpha QA found no border contact. Cells 2, 4 and 8 each have one detached pixel away from the edge.

<a id="ferret-work_cutter-hand-and-tail-edit"></a>
## Ferret engineer work_cutter hand and tail edit

Image 1 was the v1 edit target; Image 2 the immutable character/costume reference; Image 3 the approved motion scale/feet reference; Image 4 the Polar 115 layout. Both attempts set `transparent_background=true`.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact ferret-engineer-worker work_cutter atlas to edit. Image 2 is the immutable identity/costume reference; Image 3 is approved body-scale and planted-foot reference; Image 4 is Polar 115 operator-side layout only. Preserve the 4-by-2 atlas, all eight sequence phases, and the left-facing side profile. Repair frames 5, 6 and 7 (bottom row, columns 1–3) as a coherent safe-control sequence. Frame 5 withdraws both hands from the supported feed edge; keep both gloves attached to the forearms, elbows bent, complete body and full tail inside the cell. Frame 6 simultaneously presses two separated external safety controls: exactly two hands, each visibly attached to one of exactly two arms, level at the same low waist-height plane with evenly bent elbows. Remove the detached dark hand-like artifact from the left of this pose; do not leave a floating glove or stray mark. Frame 7 releases and retracts both hands toward the chest; show clearly connected wrists and arms, no detached hand marks. Keep all other frames' intent: 1 ready, 2 approach/reach, 3 touch the safe outer supported feed edge, 4 align at the supported edge clear of the blade/clamps, 8 recover to ready. Keep the same head and torso scale as neighboring frames; fit each full silhouette inside its own cell by adjusting the affected pose and its position, never by adding empty canvas around a cropped part. Provide at least 12 transparent source pixels around ears, gloves, boot soles, tail and body. Exactly two small rounded ferret ears anatomically (one near ear visible, far ear naturally occluded by skull and goggles), two arms, two legs and one striped tail. Preserve blue-lensed brass goggles, dark-green shirt, brown leather overalls/tool belt, brown gloves, dark boots, palette, lighting, linework, face and left-facing view. Character only; no cutter, paper, machine, tools, controls, labels, props, effects, text, border, checkerboard or matte. Genuine transparent alpha. Keep exact canvas dimensions and cell layout of Image 1.
</pre>

Output review:
- Attempt 1: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_cutter-v2-refined-generated.png`, SHA-256 `D1B8ACBD3F688461B4E169C6CF49D34896876C20CE65550FEB48AA9A4B3670D1`. It reduced the detached-hand problem but still had connected body pixels at the right edge in frames 5–6 and detached components in frames 6–7.
- Attempt 2: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_cutter-v3-refined-generated.png`, SHA-256 `6637D26D1071D8BC8EC358B1EE59E284E9AF2A229D05BD9EC50FB547D3FB0D60`; selected source candidate. Connected alpha QA reports no border contacts or detached hand-size pieces; frame 4 has a one-pixel detached component away from the edge.

<a id="ferret-work_press-tail-and-contact-repair"></a>
## Ferret engineer work_press tail and contact repair

Image 1 was the v1 edit target; Image 2 the immutable character/costume reference; Image 3 the approved motion/feet reference; Image 4 the Heidelberg layout. `transparent_background=true` was set.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact ferret-engineer-worker work_press 4-by-2 atlas to edit. Image 2 supplies exact identity, work_press outfit, palette, outline and left-facing view; Image 3 supplies approved body scale and planted feet; Image 4 is Heidelberg operator-side layout only. Repair only cells 3 and 4 (top row, columns 3 and 4). In cell 3, preserve the near-hand contact on the supported outer feeder but move the complete worker slightly left within the cell so the full striped tail and its outline are at least 16 transparent pixels from the right cell edge; keep the existing head/torso size and feet baseline. In cell 4, repair the forward contact pose so both gloved hands are visibly attached by continuous wrists/forearms, with no detached hand or floating piece at the left cell edge. Keep both hands on the same safe supported outer feed surface at the same mid-torso height; all fingers remain outside the rollers, nip points and platen. Keep the entire character inside each cell with at least 12 transparent pixels around ears, gloves, tail and boot soles. Preserve poses 1, 2, 5, 6, 7 and 8. Preserve exactly two ears total (near ear visible in this strict profile, far ear naturally occluded by skull and goggles), exactly two arms, two legs and one striped tail; retain blue-lensed brass goggles, dark-green shirt, brown leather overalls/tool belt, brown gloves, dark boots, face, fur shading, painterly style, camera and warm upper-left lighting. Character only; no press, paper, props, buttons, text, marks, labels, border, effects, checkerboard or matte. Genuine transparent alpha. Retain the exact 4-column by 2-row cell arrangement and canvas dimensions of Image 1.
</pre>

Output review: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_press-v2-refined-generated.png`, SHA-256 `4F5EE52CB95D2B31229D7B6FF0F77E6B522786B26ECCB84F62B76614870C8CB6`; selected source candidate. Connected alpha QA reports no border contacts; frame 7 has one isolated pixel away from the border.

<a id="ferret-work_cutter-hand-and-tail-cleanup"></a>
## Ferret engineer work_cutter hand-and-tail cleanup

Image 1 was the v2 work_cutter edit target; Image 2 was the immutable character-action identity/costume reference; Image 3 was the approved motion scale/feet reference; Image 4 was Polar 115 layout context. `transparent_background=true` was set.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact ferret-engineer-worker work_cutter atlas edit target. Image 2 is the immutable character-action identity/costume reference, Image 3 is approved motion scale and planted-foot reference, and Image 4 is Polar 115 layout context only. Edit only cells 5, 6 and 7 (bottom row, columns 1–3). The complete body and striped tail in cells 5 and 6 currently touch the right cell border: translate each whole character slightly left within its own cell, without changing head/torso scale or pose, until the complete tail outline has at least 16 transparent source pixels of right clearance. Do not crop or shorten the tail. In cell 6, repair the simultaneous two-control pose: draw exactly two attached arms and two gloves, each glove connected continuously to its wrist and forearm; remove the floating dark hand-like fragment at the left. Both gloves contact separate external safety controls at the same low waist-height plane, elbows evenly bent, hands visibly separated. In cell 7, show the released hands drawing back toward the chest with both gloves attached to their arms; remove any detached glove-shaped piece at the left edge. Preserve the sequence and keep frames 1–4 and 8 unchanged. The ferret remains left-facing and safely outside the cutter, contacting only the supported outer feed table or external controls. No part of any arm, glove, tail, ear or boot may be clipped by a cell edge; leave 12 transparent pixels around all parts. Exactly two ferret ears anatomically (one near ear visible, far ear occluded), two arms, two legs and one striped tail. Keep blue-lensed goggles, dark-green shirt, brown leather overalls/tool belt, brown gloves, dark boots, same fur palette, outline, lighting and camera. Character only; no machine, paper, blade, clamps, controls, prop, effect, text, grid, checkerboard or matte. Genuine transparent alpha. Preserve the exact 4×2 canvas dimensions and row-major cell layout.
</pre>

Output: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_cutter-v3-refined-generated.png`, SHA-256 `6637D26D1071D8BC8EC358B1EE59E284E9AF2A229D05BD9EC50FB547D3FB0D60`; selected candidate after connected-alpha QA found no border contact or detached hand-size components.

<a id="ferret-work_wrapping-margin-edit-attempts"></a>
## Ferret engineer work_wrapping margin edit attempts

These two repeated attempts used the same prompt after the selected v1 atlas showed source-alpha pixels touching cell borders. Neither output is eligible for use.

Reference roles:
- Image 1: selected v1 work_wrapping atlas, exact edit target.
- Image 2: immutable ferret worker-action atlas, exact identity, costume, style, and left-facing view.
- Image 3: approved ferret motion atlas, identity, anatomy, and planted-foot scale.

Exact prompt:

<pre>
Use case: precise-object-edit. Image 1 is the exact edit target: the selected ferret-engineer-worker work_wrapping 4-by-2 action atlas. Image 2 is the immutable worker-action atlas for exact costume, identity, painted style, and left-facing view. Image 3 is the approved motion atlas for identity, anatomy, and planted-foot scale. Preserve all eight action poses and their row-major order, but fit each complete worker inside generous transparent margins within the same existing square cell. Move and uniformly scale each pose only as needed so no opaque or semi-transparent pixel touches the cell's top, bottom, left, or right edge; leave at least 12 percent transparent clearance on all sides, including tail, ears, reaching paw, and boot soles. Keep each pose centered on the same visual scale and foot baseline. Remove any isolated stray pixels in empty margins. The sequence remains: ready facing the unseen wrapper control panel on image-left; reach; touch the exterior control; single-hand press; brief contact hold while monitoring; release and retract; stand clear and observe; return to quiet ready. Character only, no machine or prop. Subject must remain the exact gray-and-cream ferret engineer with exactly two ferret ears total (one near ear visible in this profile and the far ear naturally occluded by the skull and goggles), exactly two arms, two legs, one long striped tail, blue-lensed brass goggles, dark green shirt, brown leather overalls and tool belt, brown work gloves and dark boots. Keep the source's strict left-facing side/three-quarter view, palette, outline, lighting, face, clothing, and safe hand contact with the same exterior panel point. Feet planted throughout. Do not add visible far-side ear, extra limbs, tail, props, effects, text, gridlines, labels, background, shadow, checkerboard or matte. Output a genuine transparent 4-column by 2-row atlas in the same cell arrangement and dimensions as Image 1.
</pre>

Output review:
- Attempt 1: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_wrapping-v9a-rejected-wrong-subject.png`, SHA-256 `8324A41E7941B9EA65C81FA8FA2BB31A7E168B30D7B2D94D3BFBB6F71C1DB948`. Rejected: the generator returned a forward-facing dark cat instead of the ferret worker and changed the action poses. The file retains transparent alpha, but the character identity and machine-facing profile are wrong.
- Attempt 2: `assets/source/animation-overhaul-luna-worker-actions-v1/ferret-engineer-worker-work_wrapping-v9b-rejected-opaque-checker.png`, SHA-256 `E6C59A643582A228361388E0AF3383FB9E81FFE7DF845122CF50CBD0C9BDC612`. Rejected: the generator returned a checkerboard baked into every pixel (alpha extrema 255–255), despite the transparent-background instruction. The profile's near ear is visible and far ear occluded, but the flattened matte makes it unusable.
