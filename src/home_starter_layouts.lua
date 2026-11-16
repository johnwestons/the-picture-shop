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
    if item.kind=="sleeping_bag" then
        local Furniture=require("src.home_furniture");local Grid=require("src.placement_grid")
        local room=Layout.get(state).rooms.living
        local cx,cy=Layout.toWorld(unpack(room))
        local function try(dx,dy)
            local x,y=Grid.snap(cx+dx,cy+dy,Furniture.GRID)
            local candidate={id=item.id,kind=item.kind,x=x,y=y,direction=item.direction,location="floor"}
            local okay=Furniture.canPlace(state,candidate,{},true)
            if okay then okay=Furniture.canPlace(state,candidate,{},false) end
            if okay then item.x,item.y,item.location=x,y,"floor";return true end
        end
        for radius=0,288,24 do
            local offsets={}
            if radius==0 then offsets[1]={0,0}
            else
                for dx=-radius,radius,24 do
                    offsets[#offsets+1]={dx,-radius};offsets[#offsets+1]={dx,radius}
                end
                for dy=-radius+24,radius-24,24 do
                    offsets[#offsets+1]={-radius,dy};offsets[#offsets+1]={radius,dy}
                end
            end
            for _,offset in ipairs(offsets) do if try(offset[1],offset[2]) then return end end
        end
        return
    end
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
