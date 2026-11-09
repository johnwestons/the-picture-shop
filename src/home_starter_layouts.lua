-- World grid coordinates, registered against each apartment's fixed geometry.
local Starter={}
Starter.DATA={
    ["brick-walkup"]={couch={248,408},small_desk={440,480},mini_fridge={768,492},floor_lamp={216,468}},
    garden={couch={248,408},small_desk={432,492},mini_fridge={688,396},floor_lamp={240,462}},
    courtyard={couch={416,432},small_desk={560,528},mini_fridge={248,396},floor_lamp={432,510}},
    corner={couch={280,450},small_desk={448,516},mini_fridge={296,306},floor_lamp={248,480}},
}
function Starter.place(state,item)
    local Layout=require("src.home_layouts");local Catalog=require("src.home_furniture_catalog")
    if Catalog.ITEMS[item.kind].small then return end
    local pose=Starter.DATA[state.home.apartmentId][item.kind]
    if pose then item.x,item.y=pose[1],pose[2]
    else
        local room=Layout.get(state).rooms[item.kind=="bed" and "bedroom" or "living"]
        item.x,item.y=Layout.toWorld(unpack(room))
        item.x,item.y=require("src.placement_grid").snap(item.x,item.y,require("src.home_furniture").GRID)
    end
    item.location="floor"
end
return Starter
