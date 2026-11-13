# Cutscene Studio

Run `RUN_CUTSCENE_STUDIO.bat` to open the in-engine editor. It generates a
reproducible town from the composition's seed, then previews the production road,
terrain, camera, geared rider and motorcycle art. The editor has its own LÖVE
identity and never opens a gameplay slot or writes a game save.

## Make a cutscene

- **Start / Destination** select connected town addresses. The preview follows
  the generated road route for that seed; the actor-assist take starts at the
  first clear road stretch near the selected route entrance. **Random Route**
  picks a different connected road pair in the same town, keeping the scene
  timing and camera composition.
  **Generate High-Octane Scene** creates a separate editable composition with a
  random connected route, a varied sequence of cinematic camera shots, high
  speed changes and motorcycle maneuvers. It starts without dialogue or a
  recorded actor take so you can add lines or drive the performance yourself.
  Save the generated composition when you want to keep it.
- **Play / Pause** previews the current trim range. Click the timeline or use the
  arrow keys to scrub in quarter-second steps.
- **Actor: Motorcycle / On Foot** chooses a geared rider or walking player for
  the scene. **Drive & Record Take** or **Walk & Record Take** performs the scene
  using the game's physics in the generated studio town, without opening or
  changing a shop save. The actor starts on a clear section of the selected road.
  Motorcycle controls: **W** accelerates, **S** brakes,
  **A / D** steer, **Shift** boosts, **T** toggles automatic/manual transmission,
  and **Z / X** shift down/up in manual mode. On foot, **WASD / arrows** move and
  **Shift** runs. Press **Esc** or **Stop & Keep Take** to finish; **R** restarts
  from the clear road starting point. Drag the preview to orbit the camera and
  scroll to zoom while driving or walking. Takes are sampled at 30 fps.
- A recorded take becomes the active rider performance for the actor and route
  where it was captured. Play it back, add or adjust camera cues and dialogue,
  and set the trim range around the part you want. Changing routes keeps the old
  take available while previewing the newly selected route. Starting another
  take replaces the active take only after you finish it.
- **Add Shot** places a camera cut at the playhead. Choose from rear chase, side,
  front, overhead and wide angle presets. Select a camera marker to adjust yaw,
  tilt and zoom.
- **Record Camera Pass** replays the selected trim range while leaving the camera
  under your control. Drag the preview to orbit and scroll to zoom; press **Space**
  to pause, then resume to continue. At the end, choose **Keep Camera Pass &
  Preview** to replay the scene with those angles, or discard the pass and keep the
  previous camera track. Save the composition to keep the new camera track.
- **Add Action** places a boost, shift, brake, jump, turn or tuck cue. The player
  rides in the existing geared motorcycle art; speed cues also drive the existing
  lean and high-speed tuck presentation.
- **Add Dialogue** opens a text entry for a timed subtitle. The speaker button
  switches between Player and Grandpa.
- **Add Speed Key** adds a speed point. Select it and adjust the value in 5 mph
  steps. The playback follows the road route and maps the speed curve over its
  length.
- **Mark In / Mark Out** trims a playback range. **Reset Trim** restores the full
  composition.
- **Save Composition** writes an editable Lua data file to
  `assets/source/cutscene-studio/`. **Import to Game** also publishes that data to
  `assets/generated/cutscenes/`, where `src.cutscene.load(id)` validates and loads it.
- **Record Playback** renders the selected trim range at 25 fps and saves an
  animated GIF without the editor controls in
  `output/cutscene-studio/recordings/`. The GIF uses the game's rendered picture
  and dialogue subtitles. It is silent; motorcycle audio remains available in the
  live preview.

Keyboard shortcuts: **Space** play/pause, **Left / Right** scrub, **I / O** mark
trim in/out, **C** add a camera shot, **A** add a rider action, **D** add/edit a
dialogue line, **Ctrl+S** save, **Ctrl+R** import into the game, **M** mute or
unmute preview audio, **Delete** remove the selected cue, and **1–6** choose a
camera preset.

## First composition

`high-octane-return.lua` follows the road from Millhaven's mainland exit across
the bridge and along the farm road to Grandpa's place. It starts with a low rear
chase shot, then cuts among side, front, overhead, low tracking and wide reveal
angles. The geared player accelerates through a jump, shifts, boosts, leans into
the bends, and slows near the farm. Timed dialogue cues are visible during both
preview and recording. Use **Generate High-Octane Scene** to make another ride
with a different road pair, camera lineup, speed profile and action sequence.

Compositions use schema version 1 from `src/cutscene.lua`. Each stores its town
seed, route, actor type, camera keys, speed keys, rider actions, dialogue, trim
range and optional recorded actor take. Camera keys ease between angles, tilt
and zoom values. Project files are not included in game builds;
only files imported to `assets/generated/cutscenes/` are candidates for runtime
loading.
