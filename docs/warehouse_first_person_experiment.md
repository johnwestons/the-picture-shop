# Warehouse first-person workshop experiment

The playable first-person view was a successful development experiment. It is
now archived while the game returns to the isometric warehouse view. The live
game no longer exposes or loads the warehouse camera in single-player or
multiplayer. First-person motorcycle and truck views are separate commute
features and remain in the game.

## How the view worked

- The camera was a rendering layer over the normal warehouse world. Player
  movement, collisions with game objects, machine state, interactions, and
  multiplayer authority continued to use the existing simulation.
- A perspective shader projected warehouse floor coordinates and object
  heights into the screen. It reused the perspective math and shader support
  already used by the commute first-person renderer.
- The scene used the warehouse artwork as its floor texture, generated
  perspective geometry for the floor and enclosure, and solid fixture meshes
  for walls, shelving, doors, office furniture, and collision boundaries.
- Machines, pallets, the forklift, and pallet jack were drawn as cached meshes
  whose dimensions and animation phases came from live warehouse state. The
  windmill used a camera-facing cutout selected from its 64-frame turntable
  art.
- The camera followed the local player, with mouse or touch look and the usual
  game actions. Other players and workers continued to render from shared world
  state, so the view did not need a separate multiplayer simulation.
- During the live-game experiment, a HUD camera menu selected isometric or
  first person. F1 and C also switched views; WASD or the mobile joystick moved
  the player, and E interacted with nearby objects.

The experiment showed that the existing simulation can support a different
camera and renderer without duplicating warehouse gameplay. The main follow-up
work for a future experiment would be to tune the room scale and fixture
measurements against production art, then decide how much procedural geometry
is worth maintaining alongside the isometric scene.

## Archive contents

`archive/warehouse-first-person/` keeps the live renderer and its helper
modules, the standalone perspective lab, its test, and the unshipped 64-frame
turntable candidates. It also keeps 30 review renders and generated source
studies from the ignored lab output folder. The former lab launcher and
atlas-generation scripts are preserved there as historical development tools.
The old launcher requires its bootstrap hook to be restored before it can run.
The archived modules are not loaded by the game or copied into the runtime
package.

Six unused turntable PNGs were moved out of `assets/generated/`:

- old Polar cutter v1
- loaded paper pallet
- empty and loaded pallet jacks
- empty wood pallet
- two-color press

Together those files contain 23,074,190 bytes of PNG data (about 22 MiB). The
runtime `.love` package stores PNG files without additional compression, so
this is roughly the package size removed by those assets. The isometric
warehouse still uses the Polar cutter v2, skid-wrapper v1, and Heidelberg
Windmill 64-frame atlases. Those three remain in the runtime because the
isometric renderer uses them for machine rotation. Other vehicle first-person
art and code also remain intact.

To reuse the warehouse experiment, restore the files under the archive's `src`
and `tools` directories to their original project paths, restore any needed
turntable assets under `assets/generated/`, and reconnect the camera through
the runtime context, render, input, mobile touch, and simulation components.
The archived test records the earlier integration checks.
