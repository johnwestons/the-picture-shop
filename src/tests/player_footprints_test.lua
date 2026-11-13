local State=require("src.state")
local Condition=require("src.warehouse_condition")
local Prints=require("src.player_footprints")
local Rooms=require("src.shop_rooms")

local Test={}

function Test.run(_,check)
    local state=State.new()
    check("player_footprints_clean_warehouse_is_faint_concrete",
        Prints.surface(state,470,500,"warehouse")=="concrete")

    local story=State.new()
    story.warehouse.condition=Condition.new("story",912)
    check("player_footprints_warehouse_oil_and_dirt_change_material",
        Prints.surface(story,758,493,"warehouse")=="water"
            and Prints.surface(story,150,383,"warehouse")=="dirt")
    story.warehouse.condition.cleaned.east=true
    check("player_footprints_east_floor_cleaning_keeps_oily_puddle",
        Prints.surface(story,758,493,"warehouse")=="water")

    local barn=require("src.commute.barn_interior")
    local grocery=require("src.commute.grocery_interior")
    local station=require("src.commute.gas_station_interior")
    check("player_footprints_barn_dust_is_walkable_only",
        Prints.surface(state,200,200,"barn")=="dust"
            and Prints.surface(state,20,20,"barn")==nil)
    check("player_footprints_grocery_tile_is_walkable_only",
        Prints.surface(state,464,350,"grocery")=="tile"
            and Prints.surface(state,400,200,"grocery")==nil)
    check("player_footprints_station_tile_is_walkable_only",
        Prints.surface(state,480,500,"station")=="tile"
            and Prints.surface(state,480,650,"station")==nil)
    check("player_footprints_indoor_samples_match_room_walkmasks",
        barn.walkable(200,200) and grocery.walkable(464,350) and station.walkable(480,500))

    local roomFloor=false
    state.warehouse.bays.front_left.status="complete"
    state.warehouse.bays.front_left.optionId="floor"
    local roomKind=Rooms.definition(state,"front_left") or "floor"
    local roomMaterial=Rooms.isBuilding(state,"front_left") and "dust"
        or roomKind=="breakroom" and "wood"
        or roomKind=="storage" and "concrete" or "tile"
    local walkableSample,surfaceSample="none","none"
    for y=220,640,16 do
        for x=32,928,16 do
            local walkable=Rooms.walkable(x,y,"front_left",roomKind)
            if walkable and walkableSample=="none" then walkableSample=x..","..y end
            local surface=Prints.surface(state,x,y,"front_left")
            if surface and surfaceSample=="none" then surfaceSample=x..","..y..":"..surface end
            if walkable and surface==roomMaterial then
                roomFloor=true
                break
            end
        end
        if roomFloor then break end
    end
    check("player_footprints_shop_room_uses_walkable_floor",roomFloor,
        "kind="..tostring(roomKind).." material="..tostring(roomMaterial)
            .." walkable="..walkableSample.." surface="..surfaceSample)

    local apartment=State.new()
    apartment.home.apartmentId=apartment.home.apartmentId or "brick-walkup"
    local foundWood,foundTile=false,false
    for y=70,650,20 do
        for x=40,930,20 do
            local material=Prints.surface(apartment,x,y,"home")
            foundWood=foundWood or material=="wood"
            foundTile=foundTile or material=="tile"
            if foundWood and foundTile then break end
        end
        if foundWood and foundTile then break end
    end
    check("player_footprints_apartment_distinguishes_wood_and_tile",foundWood and foundTile)

    Prints.reset()
    local walker={sceneId="barn",x=200,y=200,moving=true}
    Prints.update(state,walker,nil,0)
    walker.x=250
    Prints.update(state,walker,nil,.2)
    local laidMarks=Prints.count()
    walker.moving=false
    Prints.update(state,walker,nil,.4)
    Prints.update(state,walker,nil,12)
    check("player_footprints_lay_and_expire_transient_steps",
        laidMarks>0 and Prints.count()==0)
    Prints.reset()
end

return Test
