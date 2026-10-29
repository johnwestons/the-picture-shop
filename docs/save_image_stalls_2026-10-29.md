# Save and cold-image stalls

Gameplay save requests now send detached shop snapshots to a background writer.
PNG demand loads now decode in a separate worker, and large GPU textures upload
in strips across updates. Source resolution, authored animation frames, anchors,
colors and transparency remain intact.

## Save behavior

`save_store.lua` contains the existing schema validation, serializer, verified
temporary writes, promotion and recovery logic. The synchronous `Save.save`,
load, delete and slot-list APIs retain their disk-operation contract.

Gameplay's `saveCurrent` queues work instead of waiting for serialization and
disk verification. Only one write runs at a time. While it runs, repeated
requests for the same profile/slot coalesce to the latest live shop. The next
immutable snapshot is captured when the worker can accept it, avoiding repeated
snapshot work while storage is busy. Worker I/O is pinned to the captured
absolute save directory, so changing the main thread's profile cannot redirect
a write. Failed writes keep the previous valid primary and retry after a
five-second backoff; failures are reported through the game message.

New shops and local/shared shop replacement finish pending writes before reusing
the live state table. Focus loss and shutdown capture the latest shop and wait
for it to finish. These lifecycle barriers deliberately await persistence;
ordinary foreground gameplay does not. Host shop updates are published when a
request is accepted, independently of disk completion. Guests do not write the
host's local saves.

## Image behavior

The image worker reads/decompresses PNGs without invoking graphics APIs. The main
thread receives one decoded image at a time. Atlases larger than 2 MiB are copied
into a drawable texture in strips of at most 2 MiB per update; smaller images
upload once. CPU decoding and GPU transfer do not run concurrently for multiple
large images. Unclaimed ready textures have a 32 MiB dispatch threshold and
expire after 20 seconds; one image can cross that threshold before dispatch
pauses. Cancellation and focus loss release pending work and partial uploads.

The pipeline covers screen asset packs, character actions, forklift and other
warehouse source art, construction/rack art, and room backgrounds/game sprites.
Loaded character and forklift poses remain available while a new view streams.
Screen changes show an animated loading panel and withhold hidden control input
until required textures are ready. Escape/back can cancel the transition.
Outgoing screen packs retire before incoming uploads, preserving the existing
inactive-cache budget instead of retaining two full screens at once.

Initial core-art startup and explicit synchronous file operations still do work
before gameplay or at their operation boundary. GPU allocation, snapshot capture
and strip staging also remain on the main thread; a byte budget is not a
guaranteed millisecond budget on every Android GPU.

## Measurements and validation

Windows LÖVE, forced 1600 by 720 phone layout; the populated save has 14 machines,
80 physical pallets, ten workers, 80 completed records and 200 emails. The save
probe uses the valid shop snapshot captured before the synthetic training phase.
Each asynchronous save sample measures snapshot capture and dispatch; its worker
completion is awaited outside that timed sample.

| Operation | Synchronous game-thread work | New game-thread work |
| --- | ---: | ---: |
| Populated save | 26.17 ms mean | 3.67 ms mean; 4.42 ms maximum |
| Cold forklift image | 35.14 ms mean | 1.77 ms maximum per loading update |
| Full cold cutter screen | Blocking pack load | 7.63 ms maximum update/draw cycle across 53 responsive frames |

The work still takes time to complete; the long serialization, disk and decode
stages no longer occupy one gameplay frame. Timings are CPU/render submission
measurements on this PC, not Android FPS or completed GPU frame times.

Evidence is in `output/performance/stalls-reviewed-20261029/measurements.json`.
The adjacent `loading-cutter.png` and `loaded-cutter.png` captures were reviewed.
Run `tools/run_performance_probe.ps1` with a fresh label and
`PICTURE_SHOP_MOBILE=1` to reproduce the old comparison rows and new stall probes.

The `late-game-performance` focus passes **596 checks and three draw frames in
each desktop and forced-mobile layout**. New checks cover detached snapshots,
coalescing, recovery after corruption, failed disk writes, retry, delete ordering,
profile changes, host notification and forced lifecycle completion. Image checks
exercise real decoding threads, bounded upload sizes, pending-pose fallback,
missing files, cancelled screen transitions, and pixel/blending equivalence at
strip boundaries. These checks also run in the normal domain suite.

All 11 runtime packaging checks pass. The Lua guard passes 631 files and 8,738
compiled functions within the project limits. Check reports are in
`output/performance/stalls-20261029/`. The older broad performance focus's stale
quote-price assertion noted in the previous report is outside this work.

ADB reports no attached Android device. Hardware frame time, GPU memory pressure
and thermal behavior still need measurement on the target phone/tablet.
