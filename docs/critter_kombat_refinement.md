# Critter Kombat refinement

The solo AI previously issued a punch or kick every frame at close range, immediately restarting attacks when one finished. This made repeated hit stun possible. The AI now waits at the start of each round, advances more slowly, attacks on spaced decisions, occasionally guards rather than perfectly reacting, and backs out when too close. Fighters receive a short grace period after an unguarded hit; another attack during that period cannot deal damage. Hit stun is shorter so the defender can move, block, or retaliate before the next AI attack.

The cabinet now has its own title screen. Choose Solo vs AI, Versus Player, or Join
Player, then choose mouse or fox before confirming. Solo AI takes the other
character. Versus players choose on their own devices, and both must confirm
before the 1.2-second Get Ready / Fight intro. Mirror matches are allowed. Combat
input and the round timer stay inactive during selection and the intro. Back
releases the reservation and returns to the cabinet title; Exit returns to the
room. Finished matches can return both participants to character selection for a
rematch. Keyboard, mouse and multitouch controls use the same flow.

Both fighters now use 48 authored poses instead of twelve: four idle, walk,
jump, block and hit poses; two knockout and victory poses; and six poses each
for jab, hook, front kick and roundhouse. Successive punches alternate jab/hook,
and kicks alternate front/roundhouse. Anticipation, extension, impact and recovery
follow the existing host hit windows and damage rules. The impact pose holds
during the active window. New jumps restart at the takeoff pose; victory and
knockout animations continue after a round ends. Guest pose clocks advance
between snapshots with a bounded 100ms render extrapolation. Fighter selection,
readiness, attack variation and match results remain host-owned and transient.
Protocol 36 carries strict character/variation fields; two full room matches fit
the existing 1,200-byte motion packet limit through three-decimal position/time
quantization.

## Jumping and configurable controls

Fighters now jump high enough to clear an opponent's body. Body collision uses
vertical separation and preserves the current order of the fighters, so a jump
can swap sides without snapping either character back. Both fighters face their
opponent after movement on every simulation step. Landing resolves overlapping
bodies on their new sides; grounded fighters and fighters jumping at the same
height still collide. Holding jump produces one jump until the input is released.
The jump pose sequence follows the approximately 1.14-second flight. Positions,
jump height and facing use the existing host-owned LAN snapshot fields.

Open **Options** on the cabinet title with a click/tap, **O**, or controller
**Start**. Keyboard, Mouse, Controller and Touch Layout tabs configure all six
actions: left, right, jump, punch, kick and block. Select an action and press its
new key/button, or move a controller stick/trigger to bind that signed axis.
Assigning a binding moves it from its previous action. Clear removes a binding;
Reset Tab restores only that device's defaults. Save applies the draft; Back
discards it. Escape and controller Back remain reserved for exiting; during
capture they cancel instead. Controller shoulders change tabs, D-pad up/down
select actions, A starts capture and Start saves. B returns from the menu when
not capturing, and can be assigned to a combat action.

Drag the touch buttons with a mouse or finger to move them. Size, opacity and
visibility are adjustable, and controls stay inside the fight area. Separate
fingers can hold movement and attacks simultaneously. Losing focus clears held
touch/mouse inputs and waits for held keys/controller inputs to return to neutral
before accepting a new press.

Defaults remain A/D or Left/Right for movement, Space/W/Up for jump, J punch,
K kick and L/S/Down block. Controller defaults are left stick/D-pad movement,
A jump, X punch, Y kick and right shoulder block. Mouse combat buttons start
unbound. Preferences are saved in `critter-kombat-controls.dat` in LÖVE's local
save directory; each device keeps its own configuration, independent of shop
saves and LAN authority.

## Generated assets and reproducibility

Built-in imagegen created four new reference atlases matching the existing mouse
and fox costumes. Their immutable sources and full prompts are in
`assets/source/critter-kombat-v2/`: `mouse-attacks.png`, `mouse-support.png`,
`fox-attacks.png`, `fox-support.png`, and the four corresponding `-prompt.txt`
files. Attack prompts request six columns by four rows (jab, hook, front kick,
roundhouse); support prompts request four columns by six rows (idle, walk, jump,
block, hit, knockout/victory). Every pose faces right; left-facing fighters use
horizontal mirroring.

Run `python tools/build_critter_kombat.py` with Pillow/numpy to locate each
complete connected pose, isolate its original RGBA from neighbouring pose
fragments, and pack it into 256-pixel cells with nearest filtering. The common
anchor is (128, 240), with a 180-pixel standing reference. Original anatomy and
color are retained. The runtime files have the same four filenames under
`assets/generated/critter-kombat-v2/`, accompanied by `manifest.json`.
Contact sheets and engine captures are under `output/critter-kombat-v2/`.

Run `PICTURE_SHOP_SMOKE_FOCUS=critter-kombat` with a fresh disposable test identity;
add `PICTURE_SHOP_MOBILE=1` for mobile input coverage. Set
`PICTURE_SHOP_KOMBAT_CAPTURE_DIR` to an existing output directory for title,
selection, intro, attack-variation and live LAN captures.

The five older cowboy tech armor concepts in
`assets/source/breakroom-minigames-v2/previews/` remain available as optional
future redesign references. This expansion uses the established fighter designs.
