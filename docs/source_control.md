# Source-control boundary

The Picture Shop is its own Git repository. It shares only the configured
author name and email with Mouse Frontier; it does not share history, remotes,
objects, or a working tree.

## Tracked project material

- LÖVE entry/configuration files, launchers, and every module under `src/`.
- Project documentation and asset research under `docs/` and `references/`.
- Asset preparation/validation tools under `tools/`, excluding Python caches.
- Authored source art under `assets/Characters/` and `assets/Machines/`.
- Promoted runtime art and preserved generated alternates under
  `assets/generated/`. Keeping the alternates in the baseline preserves work;
  a later asset-manifest cleanup can archive them with explicit provenance.
- The smoke-test runner and its checked-in ignore policy under
  `.stabilization/`.

## Canonical files temporarily retained in `output/`

Most of `output/` is disposable, but the following files are still direct
inputs to current build tools or the only approved source paired with an active
runtime asset:

- `loading-bay-open-generated.png`
- `truck-open-source.png`
- `truck-closed-source.png`
- `pallet-jack-directions-source.png`
- `pallet-jack-intermediate-directions-source.png`
- `loaded-pallet-directions-source.png`
- `polar-cutter-console-source.png`
- `polar-cutter-four-directions-final-source.png`
- `polar-cutter-intermediate-directions-source.png`
- `warehouse-client-lounge-approved.png`
- `warehouse-client-lounge-walkmask-approved.png`
- everything under `output/sprite-doctor/approved/`

These files are explicitly unignored. New canonical inputs should not be added
to `output/`; place them in a future dedicated source-art tree and update the
tools to use that stable location.

## Ignored local/generated material

- Asset-audit JSON, contact sheets, staging files, timestamped sprite-doctor
  runs, and gameplay preview screenshots under `output/`.
- Smoke reports and watchdog output under `.stabilization/`.
- Python bytecode/cache folders, editor metadata, temporary files, packages,
  and locally bundled LÖVE runtimes.
- `assets/Machines/movingPicturePress.html` and its 37 MiB webpage-support
  folder. No runtime module or current build tool reads this mirror. The files
  remain on disk; Git simply does not include them.

Ignoring a file does not authorize deleting it. Cleanup or archival of existing
local art should be a separate, reviewed task.

## Reproducibility note

All current runtime files are preserved in `assets/generated/`, and the active
asset contract is validated by both the engine smoke test and asset doctor.
Some older preparation scripts still describe historical, machine-local input
paths—for example, `prepare_warehouse_reference.py` names a temporary clipboard
file. The approved warehouse image/mask pair is therefore retained explicitly
until that script is converted to a repository-relative source path.

## Baseline validation

Before a baseline or asset-changing commit:

1. Run `RUN_SMOKE_TEST.bat`.
2. Run `python tools/asset_doctor.py --report <temporary-report-path>`.
3. Inspect `git status --short --ignored` and the staged file list.
4. Confirm no required runtime/configured path is ignored.

For a release candidate, use `RELEASE.ps1` instead of running these commands
individually. It refuses dirty, non-`main`, untracked, unpushed, or divergent
source and records the verified commit and artifact checksum in the ignored
`output/release/release-report.json` file.
