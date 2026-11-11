# Soundscape studio

Launch `RUN_SOUND_STUDIO.bat` to open Soundscape directly. Sound Studio is one application with Character voices and Soundscape sections, sharing one server. `RUN_CRITTER_STUDIO.bat` remains a shortcut to Character voices; it does not run a second editor installation. Dialogue Lab remains a separate gameplay timing harness. Direct local URL: http://127.0.0.1:43127/soundscape.

The dashboard exposes 41 existing game slots: 29 effects, three ambience layers, and nine music/radio tracks. This includes shop machinery, loading door, UI feedback, motorcycle layers, forest/warehouse ambience, phone tones, and the horn. Factory phone and horn sounds are synthesized for browser playback with the game’s tone/envelope formulas and can be tweaked like file-based sounds.

## Authoring

1. Select a slot and press **Play current sound** to hear the chosen audio immediately. **Tweak current sound** opens the workshop. Take history also includes a playable factory original and every saved version. Individual players play one at a time at source level; use the expandable mixer for layered game-level previews. Import a browser-decodable WAV/MP3/OGG/FLAC/M4A or record a microphone take. Imported files may be up to 10 minutes/116 MB; microphone sessions stop at two minutes. Imports are decoded to 48 kHz, 16-bit PCM WAV, preserving mono/stereo. A compressed song becomes larger as editable PCM; only chosen versions are published.
2. Save the source as a take or edit its start/end, gain, pitch/speed, fades, retro blend, and bit depth. Optional cleanup and normalization default off for music. Stereo stays stereo unless Convert to mono is checked. Preview rendering runs in a cancellable worker. Source files stay untouched.
3. Save the version and **Choose for this slot**. Use **Use factory sound** to revert the draft. Chosen custom takes are protected from deletion until unselected. Duplicate audio within a slot reuses the existing take.
4. Adjust slot gain/mute and the master/effects/ambience/music mixer. **Add chosen sound to preview mix** layers sounds in the browser, with individual transport and preview-loop controls. Road layers approximate a fixed game level; actual vehicle mixing varies with speed/load. Browser preview is not the live game mix.
5. **Apply to game** publishes the draft's chosen replacements and mix. Restart the game to load the new configuration. The button also saves the currently visible slot/mixer controls. Unselected imports and edits never go into builds.

Loops remain tied to their existing gameplay behavior; the editor's Loop preview switch does not change gameplay loop ownership. Check seams by ear. Edge fades soften clicks but do not create a perfect loop. Pitch changes both speed and duration. Keep source/license notes with imported assets; selected notes are copied into the published manifest.

## Files and runtime

- Draft library and mix: `assets/source/soundscape-studio/` (not packaged).
- Published assets: `assets/audio/custom/<sha256>.wav`, plus `manifest.lua` and `manifest.json`.
- Runtime adapters: `src/soundscape.lua`, `src/sound.lua`, `src/commute/audio.lua`, and `src/jukebox.lua`.
- Packaging: `runtime_custom_audio_paths` in `tools/build_mobile_package.py` verifies the published manifest and file hashes and copies only listed replacements. Old published files are not automatically deleted, but are omitted from builds when no longer listed.

Factory assets remain available as a fallback. Game event timing, existing base volumes, source streaming, and loop flags remain owned by the game; authored mixer settings multiply those volumes. Music replacements keep the existing radio slot's title. New named music tracks or new gameplay sound triggers require separate game integration.

## Dialogue Lab integration

`RUN_DIALOGUE_LAB.bat` now loads the shared `src/dialogue_profile.lua`. **Save timing for ALL characters** persists voice gain, onset delay, text reveal speed, and minimum bubble lifetime to that project file. Restart the game for changes. The initial captured tuning is 20%, 350 ms, 60 characters/second, and 2.0 seconds.

The lab preparation publishes only chosen character voice files into `assets/audio/dialogue/` with a verified manifest; launching the lab refreshes them after studio selections change. Employee dialogue uses an explicit speech-code-to-emotion mapping and falls back to that character's neutral clip. Characters without a chosen voice remain silent; they share the text timing. Grandpa's dialogue uses the same typewriter profile and retains its manual Continue interaction. The runtime honors game mute/pause/volume settings. No recording histories are packaged.

Grandpa appears as his own character in **Character voices** (`RUN_CRITTER_STUDIO.bat`) and in Dialogue Lab with his seated portrait. His current porch conversation plays **Greeting** on its first page and **Neutral** on the remaining pages, so those are the two useful takes to record first. Choose the takes in the studio, then launch Dialogue Lab to publish and preview them in the game. The remaining emotion slots are available for later Grandpa conversations.

## Checks

`node --test tools/critter-studio/studio.test.mjs tools/critter-studio/soundscape.test.mjs`

`python -m unittest discover -s tools/tests -p test_authored_audio_package.py`

`RUN_DIALOGUE_SMOKE_TEST.bat` validates selected voice decoding, runtime timing/mute/interruption, mix factors, shared profile bounds, and parsing of modified game modules without loading gameplay saves or playing smoke-test audio.
