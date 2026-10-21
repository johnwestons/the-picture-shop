CRITTER CRISIS / MOUSE FRONTIER ARCADE

From the project folder in PowerShell:
  ./tools/preview_critter_crisis.ps1

This opens the real project modules with temporary, in-memory arcade sessions.
No shop or Mouse Frontier campaign save is loaded or saved.

Menu: 1 solo Crisis, 2 LAN Crisis, 3 join, 4 Gun Range, 5 Last Stand,
6 Bandit Train Attack, 7 two players here. D-pad selects and A opens a game.
Gun Range, Last Stand and Train Attack each offer Solo, Two Players Here,
LAN Co-op, and Join Player. All fourteen Crisis stages support both players.
The preview supports solo and same-machine co-op. For LAN, connect through
the shop's existing LAN menu, then visit the same cabinet on both machines.
One player chooses LAN Co-op and the other chooses Join Player.

TWO ANDROID PHONES / PHONE AND COMPUTER
Install the same current build on both devices (Android build 53 / protocol 40).
Use the same Wi-Fi, or enable one phone's hotspot and connect the other phone.
From Local Play, one device hosts and the other joins. Either phone can host.
If discovery does not list the host, enter the host's displayed IPv4 address.
Then visit the same arcade cabinet, open Critter Crisis and choose HOST CO-OP
on one device and JOIN CO-OP on the other. The three imported games have the
same host/join options. CONNECT PHONES opens the Local Play connection menu.
Keep both games in the foreground while playing.

Each device shows one full-screen view and controls only its own player.
On phones: drag the left pad (or play area) to aim, hold FIRE to shoot,
hold COVER to duck, and tap RELOAD. Different fingers work independently.
SIGHTS toggles aiming down sights; MORE contains weapon/mode controls and
Last Stand supplies. NEXT WAVE and PLAY AGAIN are touch buttons.
Quick presses survive network sampling; repeated packets cannot repeat them.
Phone/PC sessions use these touch controls on the phone and normal mouse,
keyboard or controller controls on the PC. Same-machine mode is also retained.

TWO PLAYERS HERE
P1: mouse/WASD aim, left click/left Ctrl fire, C cover, R reload.
P2: arrows aim, Enter fire, right Shift cover, Backspace reload.
In imported games, P1 can also use Space to fire, left Shift for sights,
Tab to switch weapons, V for mode, L for Last Stand supplies.
P2: right Ctrl sights, Delete weapon, End mode, Insert supplies.
Both players have separate ammo and health. Main missions share one view;
the imported games show two views of the same targets and encounter.
The first controller used joins P2; a second controller controls P1.
Right stick aims, A/right shoulder/right trigger fires, left shoulder
covers, X reloads, Y changes weapons, left trigger raises sights.
D-pad up changes mode; down gets supplies; Start continues Last Stand.
On-screen controls support simultaneous touches for each player.
Downed players return at the next mission checkpoint or Last Stand wave.
Enter/Start restarts a completed team game; Escape/BACK leaves the cabinet.

SOLO CONTROLS

Crisis: mouse aims, left click fires, hold Space/Shift for cover, R reloads.
Controller: right stick aims, right trigger/A/right shoulder fires,
left trigger/left shoulder covers, X reloads. Start restarts a finished run.
On screen buttons support touch. P pauses the standalone preview.

Imported games: left click/Space fires, right click aims down sights, R reloads.
Last Stand/Train: C toggles cover, Tab cycles the three supplied weapons,
V changes fire mode. Gun Range uses Tab to return to course setup.
Controller: right stick aims, right trigger fires, left trigger aims,
A/right shoulder fires, X reloads, Y switches weapons, left shoulder covers.
Touch: drag to aim, use FIRE or a second finger to fire; bottom row has actions.
Escape/BACK returns to the Crisis menu. RESTART resets that game's loadout.

BLUETOOTH CONTROLLERS ON ANDROID
Pair the gamepad through Android Bluetooth settings before playing.
Each phone uses its own paired Android-compatible gamepad; touch remains usable.
The game uses Android/LÖVE gamepad input for both Bluetooth and USB controllers.
D-pad selects menus, A confirms, B returns, and Back/Select exits imported games.
On the cabinet's first menu, A opens Critter Kombat and X opens Critter Crisis.
Right stick aims; right trigger fires. X reloads and Y switches weapons.
In imported games, left trigger raises sights and left shoulder controls cover.
Last Stand: D-pad up changes fire mode, D-pad down uses supplies.
Start pauses/resumes solo imported games; A advances their results screens.
In co-op, Start advances Last Stand or restarts a finished team round.
Critter Kombat: left stick/D-pad moves, A jumps, X punches, Y kicks,
and right shoulder blocks. Its Options menu allows remapping.
Controller disconnect clears held input. After reconnecting, release triggers
before using them; use Start to resume a paused solo minigame.
Actual Bluetooth hardware remains untested when no controller is attached.

Validation and rendered screenshots:
  ./tools/preview_critter_crisis.ps1 -Review
  output/critter-crisis-review-v3/review.txt
  ./tools/preview_critter_crisis.ps1 -CoopReview
  output/critter-crisis-coop-review/review.txt
  ./tools/preview_critter_crisis.ps1 -PhoneReview
  output/critter-crisis-phone-review/review.txt
The co-op review runs both local seats and real ENet host/guest sockets on
loopback port 22967, using disposable in-memory shop and arcade state.
The phone review exercises separate device UIs for Android/Android,
PC/Android and Android/PC across all four games, including simultaneous
touches, brief taps, restart, focus changes and notch/safe-area transforms.
These automated checks do not replace a physical two-phone Wi-Fi/hotspot test.

Source import:
  ./tools/import_frontier_arcade.ps1 -Source '<Mouse Frontier 8.10 folder>'
This copies 19 original game modules and their used art/audio, namespaces
requires and asset paths, adds shared damage/update hooks without changing
solo behavior, and records original SHA256 hashes in
assets/generated/frontier-arcade/import-manifest.json. The adapters in
src/arcade_frontier provide only the disposable loadout and local preferences.
src/screens/frontier_arcade.lua handles the original solo imports.
src/critter_crisis_frontier.lua owns shared encounters and personal weapons.
src/critter_crisis_inputs.lua keeps both seats' input sources independent.
src/critter_crisis_wire.lua assembles bounded, complete LAN encounter frames.

The original enemies-and-props.png supplies four enemy identities, crates,
and barrels. enemy-run-v2.png adds movement poses. Its built-in ImageGen prompt
and origin are recorded in enemy-run-v2.source.json. Measured alpha bounds
in src/critter_crisis_art.lua prevent adjacent sprites leaking into a frame.
Enemy cover geometry is shared by the renderer, server hit testing and guests.
Motion frames follow distance traveled. Network protocol version 40 carries
both input seats, shared encounter frames, posture, travel and cover position;
LAN peers need the same build. Per-round press counters retain brief taps.
