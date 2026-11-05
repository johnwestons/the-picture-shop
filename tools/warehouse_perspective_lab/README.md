# Warehouse perspective lab

Run `RUN_WAREHOUSE_PERSPECTIVE_LAB.bat`. Third person uses the warehouse sprite
and the 64-view cutter, wrapper, and loaded-paper-pallet atlases. Tab enters first
person; the generated 3D workshop appears only in that mode. Returning to third
person resets the camera. Right drag looks around, WASD moves, Q/E turns, arrows
tilt, and the wheel zooms. C/V turns the cutter, M/N the wrapper, and [/] the
paper pallet by one 64-view step. H hides the controls.

The first-person room shell is expanded to 1.55x around its center, leaving the
machine and paper-ski positions fixed while giving the player a larger floor
area. This scale is used only by the first-person scene; the isometric view
keeps the original warehouse sprite and camera framing. The floor retains the
concrete texture. Walls, five shelving bays, dock slats,
doors, back-room extension, office furniture, cabinets and fixtures are solid
procedural geometry. First person substitutes procedural 3D meshes for the
paper cutter, skid wrapper, and paper skid. Third person keeps the illustrated
64-view sprites, and the interaction HUD stays on the same path in both views.

The Polar cutter and Heidelberg Windmill 64-view atlases are now wired into the
normal isometric warehouse renderer and machine rotation flow. The two-color
press, empty pallet, and pallet-jack turntable atlases remain separate candidate
assets in `assets/generated/`. The pallet-jack push action already has 16 gait frames in five authored
directions plus two-frame idles, mapped to eight directional sectors. That
animation stays a gait strip rather than being flattened into a static
64-angle image.

This remains a perspective blockout with approximate heights and furniture
dimensions. Doors are solid, travel and production jobs are not connected, and
the orbit view cuts away the side enclosure and ceiling. First person collides
with solid fixtures. The lab has its own identity and does not read or write game
saves.

Current first-person reviews are saved at
`output/warehouse-perspective-lab/first-person-expanded-room.png`,
`output/warehouse-perspective-lab/first-person-cutter-detail.png`, and
`output/warehouse-perspective-lab/first-person-wrapper-detail.png`.
