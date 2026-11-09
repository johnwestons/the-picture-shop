# Motorcycle and outdoor audio, first pass

The user approved this sound palette on November 1, 2026. It is wired into
the playable preview and main commute mixer. The shared Windows/Android
package copier includes all thirteen audio files and this provenance; the
offline audition reel is excluded from release packages.

The twelve PCM WAV files are original procedural sound design authored for The
Picture Shop by `tools/generate_motorcycle_audio.py`. No motorcycle recordings
or third-party synthesis samples were used. The generator uses deterministic
combustion pulses, exhaust resonances and filtered noise. `manifest.json`
records seed, duration, sample rate, peak/RMS levels and SHA-256 hashes.

This is an auditionable prototype of a small, uneven-firing four-stroke twin,
not a recording of a specific motorcycle. Four six-second RPM bands blend and
pitch with the simulation; throttle changes exhaust/intake levels. Wind and
tire friction follow road speed. Separate cues cover ignition, shutdown,
gear engagement and low-speed collision contact. Brake friction is deliberately
quiet; ordinary braking does not produce a dramatic tire skid.

`forest-ambience.mp3` is copied unchanged from the user's sibling Critter Party
project, `assets/audio/runtime/forest-ambience.mp3`. Its existing provenance in
`docs/AUDIO_SOUNDSCAPE.md` credits TinyWorlds, CC0, from
[OpenGameArt: Forest Ambience](https://opengameart.org/content/forest-ambience).
SHA-256: `9850AA1D0D5D66BD9C5DAF8BB77C6D852E01F2F4DE22F283BD5621E8BED13B75`.

The preview supports F9 mute and [ / ] volume. Focus loss silences audio.
The main commute uses the existing master/SFX/ambient controls and releases
its sources on scene exit. Each client hears its own motorcycle using the
existing public rider presentation; other riders' positional engines and
walking footsteps are not part of this first pass. Apartment door/interior
sounds remain a subsequent pass.
