# Playable motorcycle ride home

Double-click `RUN_MOTORCYCLE_PREVIEW.bat` in the project root. It locates the
installed LÖVE runtime and opens the scenic commute directly, already mounted
on the motorcycle outside the shop. The first destination is Brick walk-up;
the route map is open. No game save is loaded or written. Closing and reopening
starts a fresh practice ride.

| Control | Action |
| --- | --- |
| W | Accelerate (remappable) |
| A / D | Steer (remappable) |
| S / Space | Brake (remappable) |
| B (stopped) | Select slow reverse / forward; W moves in the selected direction |
| I (stopped) | Switch engine off/on while seated |
| E | Dismount when stopped; remount when standing beside the bike |
| H | Toggle headlight, including while riding |
| WASD / arrows on foot | Walk relative to the camera |
| Shift | Boost while accelerating |
| Tab | Choose another apartment destination |
| M | Show/hide route map |
| P / cockpit view button | Switch between the outside camera and first-person rider view |
| Backspace | Restart at the shop toward the selected apartment |
| Enter | After stopping within the destination ring, practice the return ride |
| Q / T | Orbit camera |
| R / F | Tilt camera |
| Mouse wheel / + / - | Zoom |
| Middle mouse drag | Rotate horizontally and tilt vertically (look around in first person) |
| Left Alt + middle mouse drag | Pan in outside view |
| Right mouse drag | Alternate pan in outside view |
| C / C CENTER button | Face true forward in first person; C recenters the outside camera |
| V | Automatic/manual gearbox |
| Z / X | Shift down/up in manual mode |
| F7 / F8 | Change season / scenery draw distance |
| F9 | Mute/unmute motorcycle and nature audio |
| [ / ] | Lower/raise preview volume |
| 1 / 2 / 3 | Jump to shop / bridge / ridge for scenery testing |
| Escape | Close preview |
| F10 / controller Start / top-right Controls button | Open motorcycle control mapping |

First-person view places the camera at rider eye height and follows the road
slope and motorcycle lean. A complete rider-free sprite of the actual olive
step-through bike extends beneath the handlebars through the narrow frame,
single saddle, rear rack and tail. Looking straight down or behind reveals
these parts; the camera turns up to 180 degrees either way and tilts down
90 degrees. The handlebars
respond to steering; an unlabeled curved track above the speedometer shows the
actual lean with a moving ball. Q/T and R/F look around, the wheel adjusts field
of view, and C centers your view. Steering and lean ease into and out of turns,
with separate smoothing for camera heading, pitch and bank. Looking around
leaves the cockpit attached to the bike's forward direction, so it moves across
your view. The fixed C CENTER button stays available even when looking away;
it immediately faces true forward while keeping your chosen field of view.
P switches back without changing your speed or outside camera settings.
Dismounting returns to the outside view. The main game's commute also
supports P, the cockpit button, and clicking the controller's left stick.

This is the ride-only debug sandbox: terrain, roads, motorcycle handling,
bridge, scenery, camera, instruments and four destination routes. Arrival
offers a return ride; it does not open an apartment interior or exercise the
full Friday shutdown, gear-changing or multiplayer flow. Those remain in the
main game's separate commute integration.

The cockpit has clickable ignition, direction, headlight and dismount buttons
while stopped, with hover highlights. Reverse is limited to 1.2 m/s (4.3 km/h)
and cannot boost. Stop before switching direction or ignition. Dismounting
switches off the engine; remounting starts it after the existing mount sequence.
The camera follows you on foot and the motorcycle stays where you parked it.
On-foot presentation currently uses the existing placeholder suited avatar;
the staged production riding-outfit animations are not yet integrated.

For a terminal launch, set `PICTURE_SHOP_COMMUTE_LAB=1` and
`PICTURE_SHOP_RIDE_PREVIEW=1`, then run LÖVE with the project root as its game
directory. The launcher clears inherited automated-test/capture flags.

The first motorcycle audio pass includes RPM-blended engine loops, throttle
load, ignition, gear engagement, wind, rolling/braking friction and impact.
Nature ambience is reused from Critter Party. Audio pauses when the window
loses focus. These are original synthesized motorcycle sounds for audition;
see `assets/audio/commute/SOURCES.md` for provenance and current scope.

Motorcycle mapping covers keyboard keys, mouse buttons/wheel, controller
buttons and signed axes, and configurable touch action slots plus a draggable
steering pad.
Choose a binding and press the desired input. Conflicts swap assignments;
Clear removes a binding and Reset All restores defaults. Esc/F10, controller
Start, and left-click stay reserved for menus and HUD interaction.

The main game exposes the same panel through Options > Controls > Motorcycle
Controls, or F10/controller Start during a commute. Both launch modes share
the main game's motorcycle preferences; no shop save is read by the preview.
Changes apply immediately and persist in settings.lua. They are local to each
player and do not alter another multiplayer participant's controls.

Controller defaults use the left stick to steer, right/left triggers to
accelerate/brake, the right stick to look, A to mount/dismount, Back for ignition,
left-stick click for reverse, Y for lights, and right-stick click for camera
view. The ride HUD keeps Go, Brake, Boost, and Use beside the handlebars; Map,
View, Follow, and Center stay on the right; engine, lights, transmission, reverse,
and manual shifts sit in a compact lower strip. These buttons are clickable on PC
and touch. The Touch tab includes position editing and a steering-pad preview.
Keyboard riding uses the selected bindings; on-foot WASD/arrows are unchanged.
