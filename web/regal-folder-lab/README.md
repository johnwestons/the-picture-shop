# Regal Folder Test Bench

Private standalone browser test for The Picture Shop's Regal Moll practice game.
Static HTML/JS; no backend, accounts in app code, or game save access.

`dist/folder.lua` is an experimental branch of `src/regal_folder_game.lua` from
the game repository. `engine.js` runs it in Fengari; there is no JS copy of the rules.
The user requested test-page revisions until told otherwise; publish validated
changes here without promoting them to the main game or rebuilding Android.
The eight-view machine sprite also comes from the game. `source.json` records
the rule hash, which is included with downloaded reports.

Run `node refresh-metadata.cjs` after editing the test rules, then `node test.cjs`
from this directory. The game-to-Site sync now refuses to overwrite active
experiments. Preview with
an HTTP server serving `dist/`; opening `index.html` as a file does not support
the source fetch. Publish via the Sites source helper and the identity in
`.openai/hosting.json`. Preserve the private audience unless requested otherwise.

The game and the test bench may use different UI layouts. Production UI edits
belong in the Lua screen; browser layout edits belong in `dist/`. Editing the
test page alone does not update an already installed Android app.

Third-party runtime: Fengari Web 0.1.4, downloaded from the npm registry. The
vendored distribution and its MIT license are in `dist/assets`.

Balance test 02: three work orders with explicit setup cards, a six-piece delivery
buffer, a 1.2-second boxing task, and optional timing/streak points. Early and late
catches still save paper. No time limit; stop-feed and speed 1 provide breathing room.
Gold Rhythm needs all 24 good sheets, no jams, and at least 12 perfect catches.
Work-order dialogs and hidden tabs pause the clock. Phone users have fixed catch,
box and feeder controls. The assisted setup shortcut is marked in the run/report.
