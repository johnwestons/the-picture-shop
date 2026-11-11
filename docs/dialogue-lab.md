# Character dialogue lab

Run `RUN_DIALOGUE_LAB.bat` for the playable lab, or `RUN_DIALOGUE_SMOKE_TEST.bat` for automated checks. Both use the installed LÖVE runtime and Node.js, with no additional packages.

Each launch snapshots the 14 main character previews and all explicitly chosen voice takes from `assets/audio/voices/studio.json` into `output/dialogue-lab`. Invalid entries or WAV files stop preparation with a specific error; missing emotion takes use the neutral take when available, and characters without a voice stay silent. Radio Cat's full set is required for the lab's existing smoke coverage. Relaunch after choosing different takes in the recording studio. Originals, edits, character presets, and chosen-take selections are never changed by the lab.

## Play testing

- WASD / arrow keys move the player around the enclosed room; E talks when close to the selected character.
- Use **Previous / Next** or `[` / `]` to switch through the player, workers, business visitors, vendors, and technicians. The lab shows which selected voice profile the character routes to. Shared species voices use the same routing module as game dialogue.
- Click a conversation prompt to trigger its authored emotion and example text. Space replays the selected line; Tab selects the next emotion.
- **Play full conversation** sequences all twelve emotions. **Stop / silence** or Escape interrupts playback. Losing window focus also stops dialogue.
- Characters with no selected voice remain available for text and bubble timing review and are marked as silent. Missing emotion takes use the selected neutral take when one is available, matching the game's fallback.
- Adjust voice volume, sound delay, text-reveal speed, and minimum bubble lifetime. Volume changes immediately; other changes apply to the next line. **Reset mix** restores 35% voice gain, zero delay, instant text, and 2.5 seconds minimum visibility. Use **Save timing for ALL characters** to save the current controls to the project; restart the game to apply.

The roster includes Radio Cat, Tinker Fox, Medic Fox, Ferret Engineer, Raccoon Mechanic, Business Dragon, Lizard Press Technician, Field Mouse Technician, Business Fox, Business Cat, Tan Cat, Green Blazer Cat, Blue Coaler Cat, and the player rabbit. Cat characters route to Radio Cat, raccoons to the mechanic, reptiles to Business Dragon, and canines to Medic Fox unless an individual voice is selected. Tinker Fox remains individual-only until her own takes are selected.

The initial mix leaves headroom; final loudness still needs listening on your speakers/headphones and eventual comparison with game ambience. Peak and RMS readouts describe each recording, not perceived loudness or hardware output level. “Actual onset” is the application playback request time relative to bubble appearance, not measured sound-device latency.

Use greeting for onset, agreement/disagreement for quieter recordings, and surprised for loudness contrast. Test rapid prompt changes for interruptions, a positive delay for synchronization, and typewriter mode for longer text. The bubble lasts at least through the voice and text reveal. Each line triggers one non-looping sound, not a sound per letter. Subsequent dialogue stops the previous source and cancels pending playback.

## Shared game behavior and isolation

The room uses the project's idle sprites and shared `src/speech_bubble.lua` bubble drawing implementation. The lab uses authored example lines in `tools/dialogue_lab/dialogue.lua`. Live employee speech uses `src/dialogue_profile.lua`, `src/dialogue_presentation.lua`, and the same `src/dialogue_voices.lua` routing module as the lab. Chosen voice clips are published at lab preparation and included in game builds via their manifest. The simplified test room deliberately has no game simulation, inventory, networking, or ambience.

The launcher resets only the lab's disposable `the-picture-shop-dialogue-lab` LÖVE identity, and never loads the main game's saves. Lab code writes no gameplay saves. Snapshot files and reports stay under ignored `output/dialogue-lab`; the normal package allowlist still excludes studio takes. The smoke run is silent.

## Smoke coverage

`output/dialogue-lab/smoke-report.txt` records the chosen Radio Cat clip decoding, duration, peak/RMS measurements and PCM bounds, plus deterministic tests for immediate bubbles, delayed playback, one-shot triggering, interruption, canceled pending audio, typewriter reveal, expiration, and shared bubble wrapping. A successful run exits zero and ends in `DIALOGUE_SMOKE_OK`. This validates the playback scheduler and selected Radio Cat files; it cannot judge whether a performance sounds good or measure device latency.

Implementation: `prepare.mjs` builds the isolated character-and-voice snapshot; `dialogue.lua` owns event timing; `main.lua` provides the character room and controls; `smoke.lua` runs assertions with mock playback sources after decoding the Radio Cat takes.
