-- Shared starting-home choices. Prices are game balance values in cents.
local Catalog={ORDER={"brick-walkup","garden","courtyard","corner"},ALLOWANCE_CENTS=30000}
Catalog.APARTMENTS={
    ["brick-walkup"]={name="Brick walk-up",condition="Shabby",rentCents=45000,
        description="Scuffed boards, old fittings, and the lowest rent."},
    garden={name="Garden apartment",condition="Worn but serviceable",rentCents=60000,
        description="A practical little home with well-used finishes."},
    courtyard={name="Courtyard apartment",condition="Fair / cared for",rentCents=80000,
        description="Warm floors and a tidier, comfortable starter home."},
    corner={name="Corner apartment",condition="Good",rentCents=100000,
        description="Refreshed finishes at the top of the starter budget."},
}
Catalog.PRESETS={
    empty={label="Empty",description="One laptop on the fixed kitchen counter. No other furnishings or groceries.",
        contents={laptop=1}},
    modest={label="Modestly furnished",description="Laptop, cheap bed, worn couch, mini fridge, small desk, chair, floor lamp, clock, cup, and 4 basic meals.",
        contents={laptop=1,bed=1,couch=1,mini_fridge=1,small_desk=1,chair=1,floor_lamp=1,clock=1,cup=1,basic_meal=4}},
}
for id,entry in pairs(Catalog.APARTMENTS) do
    entry.floorPath="assets/generated/apartments-v1/"..id.."-floor.png"
    entry.wallPath="assets/generated/apartments-v1/"..id.."-walls.png"
end
function Catalog.roll(random)
    return Catalog.ORDER[(random or math.random)(#Catalog.ORDER)]
end
return Catalog
