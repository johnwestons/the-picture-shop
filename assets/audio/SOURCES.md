# Audio credits and source ledger

The Picture Shop's 16 runtime cues combine deterministic filtered noise and
physical-model layers with transformed field recordings from Freesound. The
recordings were trimmed, downmixed to mono, resampled to 44.1 kHz, filtered,
layered, faded, looped where applicable, and peak-normalized. They are not
redistributed as standalone source recordings.

This file ships inside desktop and Android game packages. Exact byte counts,
SHA-256 fingerprints, and generator-relative paths are recorded in
`source_manifest.json`.

## Attribution-required recordings

- **sliding_door_opening.wav** by **Joe DeShon (joedeshon)** —
  <https://freesound.org/s/134715/> — licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Used in loading-door,
  cutter, and skid-wrapper mechanism layers.
- **left_foot_stone.wav**, **left_foot_gravel.wav**, and **right_foot_stone.wav**
  by **GlennM** — <https://freesound.org/s/386519/>,
  <https://freesound.org/s/386522/>, and <https://freesound.org/s/386525/> —
  licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
  Used as transformed impact, contact, and material-foley layers.
- **260425_160902_FR_Steam train stopping at St-Valery** by
  **Kevin Luce (kevp888)** — <https://freesound.org/s/854736/> — licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Used as a transformed
  truck-arrival and press-start mechanical layer.
- **260426_112308_FR_Steam train travelling** by **Kevin Luce (kevp888)** —
  <https://freesound.org/s/855304/> — licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Used as transformed
  press-running and warehouse-ambience layers.

## CC0 recordings

Attribution is not legally required for these sources, but they are listed for
complete provenance:

- **door - open 01.wav** by **Anthousai** —
  <https://freesound.org/s/398750/> —
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- **Click menu** by **SLV443** — <https://freesound.org/s/733769/> —
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- **Slash** by **qubodup** — <https://freesound.org/s/442903/> —
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## Reproduction

The original recordings are intentionally not committed because the two train
files alone exceed 247 MiB. Place the licensed files in the relative locations
listed by `source_manifest.json`, then either pass that directory explicitly:

```powershell
python tools/generate_sfx.py --source-root "C:\path\to\soundEffects"
```

or set `PICTURE_SHOP_AUDIO_SOURCES`. The current development default points to
the `Mouse Frontier 8.10/sounds/soundEffects` sibling project. Generation stops
before writing output if any source is absent or fails its size/SHA-256 check.
Use `--verify-only` to audit inputs and `--preview` to make the ignored audition
reel in addition to the 16 shipping cues.
