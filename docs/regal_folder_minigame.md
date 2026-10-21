# Regal Moll folder practice run

## Standalone browser test

Open the private [Regal Folder Test Bench](https://picture-shop-regal-folder-lab.rockycoot12.chatgpt.site)
and sign in with the owning ChatGPT account. No game launch, equipment purchase
or game save is needed. Setup, proofing, feeding, catching, boxing, jams and all
eight machine views are available. Download a test report to share the current
state and recent actions in this chat when requesting changes.

The browser runs an experimental branch of `src/regal_folder_game.lua` in a vendored
Lua runtime. Balance test 02 adds three job-specific work orders, a six-piece
delivery buffer, timed boxing, and optional catch-timing/streak bonuses. Open
**Work order** for stock, quantities, required/current settings, and a proof checklist;
production pauses while the ticket is open. **New batch** cycles the three jobs.
`tools/sync_regal_folder_lab.py` refuses to overwrite experimental rules.
Publish revisions to this test page until the user requests otherwise. These
experiments do not change the in-game screen or installed APK. The Site source lives in `sites/regal-folder-lab`
with its own Sites-managed Git repository and private hosting identity.

## In the shop

The Regal Moll folder is optional equipment. New shops and existing shops that
have not purchased one have no folder on the warehouse floor. Buy **Regal Moll
practice folder** from the Used Machinery salesman, or use **COMPUTER > WWW >
MACHINES** and check out the online order. Dealer purchases are placed in a clear
floor location immediately; online purchases arrive by flatbed and appear after
unloading. Ownership and position are saved. Selling the folder removes it from
the floor again.

The temporary in-game base price is $18,000; the normal condition-based machinery
pricing produces a $12,600 dealer offer or $17,190 online offer. This is game
balancing, not a real-world price. Financing uses the normal Credit tab.

Walk to a purchased folder and press **E** when the practice-batch prompt appears.
The two workstations can be played with the on-screen controls or keyboard; a
second local player is not required. The previous free practice prop no longer
renders, blocks movement, or offers an interaction. No save migration or reset is
required for its removal. This change requires matching protocol 41 game builds
for Local Play; older installed APKs still contain the free prop.

The shop-floor Regal Moll prop opens a 24-piece practice batch with two workstations. The machine operator sets the fold stop, side guides, and feeder air, inspects a test sheet, starts the run, replenishes the feed pile, and stops or clears faults. The catcher collects each delivered piece and packs six per box. If the delivery backs up, the machine jams and the operator must stop, clear it, and check a new proof. The `V` key cycles the eight supplied machine views. Mouse and touch buttons provide the same controls as the keyboard.

This is a local practice minigame. It does not consume customer stock, award cash, or complete a paid job. A guest worker in network play cannot open it yet because the production session is not shared with the host.

Research used for the gameplay:

- [B&R Moll Regal System](https://mollbrothers.com/product/regal/): belt transport, buckle and tipper fold plates, dual pumps, sheet spacing, and batch controls.
- [B&R Moll Marathon System with Versafold](https://mollbrothers.com/product/marathon/): pulse feeding, pile height control, buckle plate, and heavy cover stock range.
- [Formax FD 340 operator manual](https://formax.com/wp-content/uploads/2023/09/FD-340-Op-Manual-Rev-2.pdf), pages 5–7: fold stop and side-guide setup, test-sheet check, adjustment before production, and batch counting. This is a comparable folder manual, not a Regal/Marathon service manual. A public machine-specific operation manual was not found.

The target values, eight-sheet feed pile, one-sheet catching actions, six-piece boxes, and jam threshold are game abstractions. They are not calibration or safe operating instructions for the real machine.
