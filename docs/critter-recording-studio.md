# Critter Recording Studio

Double-click `RUN_CRITTER_STUDIO.bat` in the project root. The local server uses Node.js (no npm packages) and opens your default browser at http://127.0.0.1:43127. Use current Edge or Chrome and allow microphone access. The server binds only to this computer.

Choose a character and an emotion, press Record, perform your sound, then Stop. Listen before pressing Save take to project. Discard & retry removes only the unsaved take. Every save creates a unique file; re-recording never overwrites earlier takes. The checklist counts saved takes for each emotion, and the library plays all takes for the selected character/emotion. Refresh rescans disk. Recording is capped at two minutes per take.

Files live in `assets/audio/voices/<character-id>/<emotion>/take-<timestamp>-<id>.wav`. They are real uncompressed PCM WAV, mono, 48,000 Hz, 16-bit. Capture downmixes microphone channels and resamples when necessary; the server validates the format before writing. Browser microphone enhancements are requested off. The live peak warning helps avoid clipped recordings. Originals are not normalized or denoised; cleanup can produce separate derived assets later. The game uses LÖVE, which can load PCM WAV; existing effects use differing sample rates, so 48 kHz here is the voice recording master format.

The roster reads the project's character-motion manifests, worker catalog, and town-character definitions, using stable character IDs rather than randomized save-game employee names. The twelve starter sound categories are an authoring checklist, not claims that gameplay already has audio triggers for every emotion. Saved takes are not yet assigned to dialogue playback in the game. This tool does not load, run, or modify the game or its saves.

If saving fails, the take remains in the browser and Download WAV provides a recovery copy. Closing or reloading with a pending take triggers a browser warning. Use headphones when reviewing old takes; playback is paused before recording. For blocked microphones, check the browser's site permissions and Windows Settings > Privacy & security > Microphone.

Manual start: `node tools/critter-studio/server.mjs`. Stop a manually launched server with Ctrl+C. The launcher reuses an already-running studio. Run verification with `node --test tools/critter-studio/studio.test.mjs`.

## Editing saved takes

Click **Tweak this take** in the library. Compare the source with **Preview changes**, then **Save edited version** under a descriptive name. Presets include Gentle cleanup, Soft 8-bit, Crunchy arcade, and Tiny critter. Controls provide manual start/end trim, automatic outer-silence trim, rumble reduction, a soft noise gate, peak normalization, pitch/speed, bit quantization, sample hold, and dry/effect blend. The gate reduces noise in quiet gaps; it is not spectral noise removal. Pitch changes speed and duration as well. Short edge fades reduce clicks.

Processed versions use `edit-<content-hash>.wav` alongside the original, with a small `.wav.json` settings/source sidecar. Originals are never overwritten. Reopening a version restores its settings against its source instead of applying the effect again to already-processed audio. Identical output is deduplicated within the character/emotion folder; it retains its existing label. Previews live only in browser memory, and a preview download provides recovery if saving fails. Changes invalidate the old preview so Save always matches the current settings.

Full-quality mono 48 kHz, 16-bit PCM remains the default. Optional compact 24 kHz output halves the audio data for the same duration; anti-alias filtering is applied before resampling. The 8-bit control is an audible effect, not the WAV storage bit depth. The library shows individual and total WAV sizes.

Keep as many takes and emotions as useful for future dialogue. The checklist puts common conversational sounds first. `tools/build_mobile_package.py:copy_runtime` uses a closed list of audio sources shared by Windows and Android packaging; **neither recordings nor edited versions under `assets/audio/voices/` are included**. When dialogue audio is integrated, explicitly add only chosen runtime clips to that packaging list. Saving an edited version in the studio does not enable it in the game or include it in a release.

## Character voices and chosen takes

Use **Save as character voice** in the editor to keep that character's current effects and output quality. Saving again replaces the preset after confirmation. Manual start/end points are deliberately excluded. New edits of original recordings load the character preset automatically; **Apply character voice** applies it to an already-open editor while preserving its trim points. Previously edited versions reopen with their own saved recipe until you explicitly apply the character voice. Preview and save the result as usual; saving a preset does not batch-rewrite any WAVs.

**Use this take** designates one original or edited take for a character/emotion. Choosing another replaces that selection; the starred button clears it. Presets and selections persist in `assets/audio/voices/studio.json`. A chosen take is an authoring decision, not automatic runtime integration or inclusion in game packages.

**Delete take** permanently removes the WAV and its settings sidecar after a confirmation identifying the sound. Deleting the chosen take clears its selection. Sources with dependent edited versions cannot be deleted until those edits are deleted, preserving their editable source. Deletion tests use temporary synthetic files, never the user's recordings.

## Apply a character voice in bulk

After saving a character voice, close the editor and click **Apply voice to all originals** beneath the character selector. The studio refreshes the saved preset and take list, then processes every original for that character across all emotions, one at a time. It snapshots that preset for the whole run, uses each recording's full length plus the preset's automatic silence trim, and saves separate **Character voice** edited versions. Existing edited takes are not processed again; chosen-take selections are unchanged.

Progress and created/reused/failed counts appear beside the button. Identical audio is reused rather than duplicated. Per-take failures are listed and the remaining takes continue; rerunning safely retries failures and reuses successful outputs. Keep the tab open until it finishes. Neither originals nor other characters' files are changed. Edited versions remain excluded from game builds until explicitly integrated.
