-- The original combat values for the three included arcade firearms.
local Catalog={weaponProgression={'frontier-22-lever-rifle','frontier-9mm-service-pistol','sawed-off-shotgun'}}
Catalog.weaponCombat={
    ['frontier-22-lever-rifle']={kind='ranged',range=32,ammo='22lr',capacity=12},
    ['frontier-9mm-service-pistol']={kind='ranged',range=24,ammo='9mm',capacity=15},
    ['sawed-off-shotgun']={kind='ranged',range=12,ammo='12-gauge',capacity=2},
}
function Catalog.weaponFamily() return 'firearms' end
return Catalog
