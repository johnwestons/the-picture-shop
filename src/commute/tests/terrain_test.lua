local Terrain=require('src.commute.terrain')
local Test={}

local function finite(value)
    return type(value)=='number' and value==value and value~=math.huge and value~=-math.huge
end

function Test.run(check)
    local first=Terrain.new()
    local second=Terrain.new()
    check('commute_terrain_fixed_identity',first.seed==4261 and first.size==512
        and first.streamed and first.plan==first.terrain)

    local repeatable=true
    for _,point in ipairs({{56,56},{132,150},{280,200},{330,270},{390,220},{458,458}}) do
        local x,z=point[1],point[2]
        repeatable=repeatable and first:height(x,z)==second:height(x,z)
    end
    check('commute_terrain_seeded_samples_repeat',repeatable)

    local finiteAndBounded=true
    for z=56,458,32 do
        for x=56,458,32 do
            local h=first:height(x,z)
            finiteAndBounded=finiteAndBounded and finite(h)
                and h>=-1.2 and h<=first.maxHeight
        end
    end
    check('commute_terrain_inland_samples_finite_and_bounded',finiteAndBounded)

    local hill=first:baseHeight(132,150)
    local westTerrace=first:baseHeight(270,200)
    local eastBank=first:baseHeight(390,220)
    check('commute_terrain_west_hills_above_terraces',hill>=8 and hill<=20
        and westTerrace>=2.5 and westTerrace<=6.5 and hill>westTerrace+3)
    check('commute_terrain_east_bank_remains_inland',eastBank>=3.5 and eastBank<=8.5)

    local center=first:riverCenterX(270)
    local centerHeight=first:height(center,270)
    local waterId=first.plan:waterIdAt(center,270)
    local northX=first:riverCenterX(200)
    local southX=first:riverCenterX(350)
    check('commute_terrain_river_is_a_north_south_channel',center==330
        and centerHeight<0 and first:rawHeight(center,270)<0
        and waterId=='town-river' and math.abs(northX-southX)>12)

    local bridge=first.bridgeCrossing
    check('commute_terrain_bridge_crossing_is_pinned',bridge.x0==290 and bridge.x1==380
        and bridge.z==270 and bridge.x==330)

    local bounds=first.playableBounds
    check('commute_terrain_playable_bounds_are_pinned',bounds.x0==56 and bounds.z0==56
        and bounds.x1==458 and bounds.z1==458)

    local northBoundary=first:height(56,56)
    local southBoundary=first:height(458,458)
    check('commute_terrain_playable_bounds_are_inland',northBoundary>0 and southBoundary>0)

    local canopy,moisture,rockiness=first:habitat(132,150)
    check('commute_terrain_habitat_axes_are_available',finite(canopy) and finite(moisture)
        and finite(rockiness) and canopy>=0 and canopy<=1 and moisture>=0 and moisture<=1
        and rockiness>=0 and rockiness<=1)
end

return Test
