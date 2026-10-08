local Rooms=require("src.shop_rooms")
local Layout=require("src.warehouse_layout")
local Storage=require("src.pallet_storage")
local Avatar=require("src.multiplayer_avatar_renderer")
local Beacon=require("src.interaction_beacon")
local cache=require("src.texture_cache").new(24*1024*1024,3)
local Renderer={}
local activeImage,activePath
local dockMesh,dockProgress,dockImage
function Renderer.pruneCache() cache:prune() end
function Renderer.clearCache()
    cache:clear()
    if activeImage then activeImage:release();activeImage,activePath=nil,nil end
    if dockMesh then dockMesh:release();dockMesh,dockProgress,dockImage=nil,nil,nil end
end
function Renderer.selectScene(sceneId)
    if sceneId=="warehouse" and activeImage then
        cache:put(activePath,activeImage);activeImage,activePath=nil,nil
    end
    cache:prune()
end
local function background(state,sceneId,assets)
    if sceneId=="warehouse" then return assets.get("warehouse") end
    local path=Rooms.paths[Rooms.definition(state,sceneId)]
    if not path then return nil end
    if activePath~=path then
        if activeImage then cache:put(activePath,activeImage) end
        activeImage=cache:take(path) or love.graphics.newImage(path)
        activeImage:setFilter("linear","linear")
        activePath=path
    end
    return activeImage
end
function Renderer.drawBackground(state,sceneId,assets)
    local image=background(state,sceneId,assets)
    if image then love.graphics.setColor(1,1,1);love.graphics.draw(image,0,0,0,960/image:getWidth(),678/image:getHeight()) end
    return image
end
function Renderer.drawShelves(assets,state,sceneId,drawPallet)
    local rackId=sceneId.."-rack"
    if sceneId~="warehouse" and Rooms.definition(state,sceneId)~="storage" then return end
    if not state.storage or not state.storage.racks[rackId] then return end
    local slots=Storage.slots(state,rackId)
    for row=2,1,-1 do for column=1,5 do
        local item=slots[row][column] and Storage.find(state,slots[row][column])
        if item then
            local point=Layout.rackPoint(rackId,row,column)
            drawPallet(assets,{pallet=item.pallet,job=item.job,vendor=item.vendor,x=point.x,y=point.y,
                visualScale=sceneId=="warehouse" and 0.58 or 0.82,hideWorldLabel=true})
            -- Restore the authored front lip over the load; its shelf contact
            -- stays visible and the skid reads behind, rather than on a beam.
            local image=background(state,sceneId,assets)
            local halfWidth=sceneId=="warehouse" and 31 or 52
            love.graphics.stencil(function()
                love.graphics.polygon("fill",point.x-halfWidth,point.y+2,
                    point.x+halfWidth,point.y+10,point.x+halfWidth,point.y+15,point.x-halfWidth,point.y+7)
            end,"replace",1)
            love.graphics.setStencilTest("greater",0)
            love.graphics.setColor(1,1,1)
            love.graphics.draw(image,0,0,0,960/image:getWidth(),678/image:getHeight())
            love.graphics.setStencilTest()
        end
    end end
end
function Renderer.addShelfActors(actors,assets,state,drawPallet)
    actors[#actors+1]={y=0,layer=-1,draw=function() Renderer.drawShelves(assets,state,"warehouse",drawPallet) end}
end
local function tableForeground(state,sceneId,assets)
    local polygon={675,184,724,172,779,186,779,218,730,231,674,214}
    love.graphics.stencil(function() love.graphics.polygon("fill",unpack(polygon)) end,"replace",1)
    love.graphics.setStencilTest("greater",0)
    Renderer.drawBackground(state,sceneId,assets)
    love.graphics.setStencilTest()
end
function Renderer.drawRoom(world,assets,characters,state,remotePlayers,drawPlayer,drawPallet)
    local sceneId=Rooms.scene(world.player)
    Renderer.drawBackground(state,sceneId,assets)
    Renderer.drawShelves(assets,state,sceneId,drawPallet)
    local visible={[world.player.character]=true}
    local actors={{y=world.player.y,draw=drawPlayer}}
    if Rooms.definition(state,sceneId)=="breakroom" then
        actors[#actors+1]={y=231,draw=function() tableForeground(state,sceneId,assets) end}
    end
    local EmployeeRenderer=require("src.employee_renderer")
    for _,entry in ipairs(EmployeeRenderer.entries(state)) do if Rooms.employeeScene(entry)==sceneId then
        visible[(entry.worker or entry.application).character]=true
        actors[#actors+1]={y=Rooms.seats[3].y,draw=function()
            local oldX,oldY=entry.actor.x,entry.actor.y
            entry.actor.x,entry.actor.y=Rooms.seats[3].x,Rooms.seats[3].y
            EmployeeRenderer.draw(entry,characters)
            entry.actor.x,entry.actor.y=oldX,oldY
        end}
    end end
    for _,p in ipairs(remotePlayers or {}) do if Rooms.sameScene(p,world.player) then
        visible[p.character]=true
        actors[#actors+1]={y=p.y,draw=function() Avatar.draw(characters,{p},state) end}
    end end
    characters.retainCharacters(visible,true)
    table.sort(actors,function(a,b) return a.y<b.y end)
    Beacon.drawUnderlay(world.getInteraction(),world.player.interactionClock,{})
    for _,actor in ipairs(actors) do actor.draw() end
    Beacon.drawOverlay(world.getInteraction(),world.player.interactionClock,{})
    love.graphics.setColor(.02,.035,.04,.90);love.graphics.rectangle("fill",12,80,245,52,5)
    love.graphics.setColor(.96,.92,.78,1);love.graphics.print(Rooms.name(state,sceneId),24,90)
    love.graphics.setColor(.76,.85,.86,1);love.graphics.print("Use the rear-left door to return",24,111)
end
function Renderer.drawDock(assets,door)
    local progress=door.progress or 0
    if progress<=0 then return end
    local image=assets.get("warehouse")
    local aperture=require("src.config").truck.aperture
    local polygon={};for _,p in ipairs(aperture) do polygon[#polygon+1]=p.x;polygon[#polygon+1]=p.y end
    love.graphics.stencil(function() love.graphics.polygon("fill",unpack(polygon)) end,"replace",1)
    love.graphics.setStencilTest("greater",0)
    love.graphics.setColor(.09,.12,.14,1);love.graphics.polygon("fill",unpack(polygon))
    love.graphics.setColor(1,1,1)
    -- Texture only the shutter polygon. Translating the entire background
    -- would paint concrete floor into the open doorway below the lifted door.
    local vertices={}
    for _,p in ipairs(aperture) do vertices[#vertices+1]={p.x,p.y-progress*155,p.x/960,p.y/678,1,1,1,1} end
    if not dockMesh then dockMesh=love.graphics.newMesh(vertices,"fan","dynamic")
    elseif dockProgress~=progress then dockMesh:setVertices(vertices) end
    if dockImage~=image then dockMesh:setTexture(image);dockImage=image end
    dockProgress=progress
    love.graphics.draw(dockMesh)
    love.graphics.setStencilTest()
end
return Renderer
