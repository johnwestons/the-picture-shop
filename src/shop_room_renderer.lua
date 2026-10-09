local Rooms=require("src.shop_rooms")
local Layout=require("src.warehouse_layout")
local Storage=require("src.pallet_storage")
local Avatar=require("src.multiplayer_avatar_renderer")
local Beacon=require("src.interaction_beacon")
local Games=require("src.breakroom_games")
local cache=require("src.texture_cache").new(24*1024*1024,3)
local Renderer={}
local activeImage,activePath
local dockMesh,dockProgress,dockImage
local gameImages={}
local GAME_ASSETS={air_hockey="air-hockey-table.png",basketball="basketball-hoop.png",
    critter_kombat="critter-kombat-cabinet.png",ball="basketball.png"}
local function gameImage(id)
    if gameImages[id] then return gameImages[id] end
    local path="assets/generated/breakroom-games-v1/"..GAME_ASSETS[id]
    if not love.filesystem.getInfo(path) then return nil end
    local image=love.graphics.newImage(path)
    image:setFilter("linear","linear")
    gameImages[id]=image
    return image
end
local function drawGame(id,x,y)
    local image=gameImage(id)
    if image then
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(image,x-image:getWidth()/2,y-image:getHeight())
    end
end
function Renderer.drawBall(x,y) drawGame("ball",x,y) end
function Renderer.pruneCache() cache:prune() end
function Renderer.clearCache()
    cache:clear()
    require("src.basketball_renderer").clear()
    for id,image in pairs(gameImages) do if image.release then image:release() end;gameImages[id]=nil end
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
    local kind=Rooms.definition(state,sceneId)
    local stage=Rooms.constructionStage(state,sceneId)
    local path=stage and Rooms.constructionPaths[kind] and Rooms.constructionPaths[kind][stage]
        or Rooms.paths[kind]
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
    if sceneId~="warehouse" and (not Rooms.isComplete(state,sceneId) or Rooms.definition(state,sceneId)~="storage") then return end
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
function Renderer.drawLobbyForeground(assets,seat)
    local polygon=seat and require("src.warehouse_registration").lobbyForegrounds[seat.name]
    local image=assets.get("warehouse")
    if not polygon or not image then return end
    love.graphics.stencil(function() love.graphics.polygon("fill",unpack(polygon)) end,"replace",1)
    love.graphics.setStencilTest("greater",0);love.graphics.setColor(1,1,1)
    love.graphics.draw(image,0,0,0,960/image:getWidth(),678/image:getHeight())
    love.graphics.setStencilTest()
end
local function tableForeground(state,sceneId,assets)
    local polygon={675,184,724,172,779,186,779,218,730,231,674,214}
    love.graphics.stencil(function() love.graphics.polygon("fill",unpack(polygon)) end,"replace",1)
    love.graphics.setStencilTest("greater",0)
    Renderer.drawBackground(state,sceneId,assets)
    love.graphics.setStencilTest()
end
function Renderer.drawRoom(world,assets,characters,state,remotePlayers,drawPlayer,drawPallet,drawPalletJack,drawPlacement)
    local sceneId=Rooms.scene(world.player)
    Renderer.drawBackground(state,sceneId,assets)
    if drawPlacement then drawPlacement() end
    Renderer.drawShelves(assets,state,sceneId,drawPallet)
    local visible={[world.player.character]=true}
    local jack=state and require("src.pallet_jack").ensure(state,require("src.config").palletJack)
    local jackInScene=jack and jack.sceneId==sceneId
    local playerId=tonumber(world.player.id) or 1
    local localJackOperator=jackInScene and jack.operating and jack.operatorPlayerId==playerId
    local actors={}
    if not localJackOperator then actors[#actors+1]={y=world.player.y,draw=drawPlayer} end
    if Rooms.isComplete(state,sceneId) and Rooms.definition(state,sceneId)=="breakroom" then
        actors[#actors+1]={y=231,draw=function() tableForeground(state,sceneId,assets) end}
        for _,id in ipairs(Games.ORDER) do
            if Games.owns(state,sceneId,id) then
                local fixture=Games.CATALOG[id]
                actors[#actors+1]={y=fixture.y,draw=function() drawGame(id,fixture.x,fixture.y) end}
            end
        end
    end
    for _,ball in ipairs(require("src.basketball").renderRecords(state)) do
        if ball.sceneId==sceneId and (ball.mode=="placed" or ball.mode=="flight") then
            actors[#actors+1]={y=ball.y,draw=function() drawGame("ball",ball.x,ball.displayY or ball.y) end}
        end
    end
    local builder=state and state.constructionWorker
    if builder and builder.phase=="working" and builder.bayId==sceneId and Rooms.isBuilding(state,sceneId) then
        local bay=Layout.bay(sceneId)
        local roomWorker={}
        for key,value in pairs(builder) do roomWorker[key]=value end
        roomWorker.x,roomWorker.y=bay.workPoint.x,bay.workPoint.y
        actors[#actors+1]={y=roomWorker.y,draw=function()
            require("src.warehouse_renderer").drawConstructionWorker(roomWorker,state)
        end}
    end
    local EmployeeRenderer=require("src.employee_renderer")
    local jackEmployee
    for _,entry in ipairs(EmployeeRenderer.entries(state)) do if Rooms.employeeScene(entry)==sceneId then
        if jackInScene and jack.operating and jack.operatorEmployeeId==entry.actor.id then
            jackEmployee=entry
        else
        visible[(entry.worker or entry.application).character]=true
        actors[#actors+1]={y=Rooms.seats[3].y,draw=function()
            local oldX,oldY=entry.actor.x,entry.actor.y
            entry.actor.x,entry.actor.y=Rooms.seats[3].x,Rooms.seats[3].y
            EmployeeRenderer.draw(entry,characters)
            entry.actor.x,entry.actor.y=oldX,oldY
        end}
        end
    end end
    local jackRemote
    if jackInScene and jack.operating and jack.operatorPlayerId then
        for _,p in ipairs(remotePlayers or {}) do
            if tonumber(p.id)==jack.operatorPlayerId then jackRemote=p;break end
        end
    end
    if jackInScene and drawPalletJack then
        if jackRemote then visible[jackRemote.character]=true end
        if jackEmployee then visible[(jackEmployee.worker or jackEmployee.application).character]=true end
        actors[#actors+1]={y=jack.y,layer=jack.operating and 1 or 0,draw=function()
            local pose=require("src.pallet_jack").visualPose(state,require("src.config").palletJack)
            local operator=jackRemote and function() Avatar.draw(characters,{jackRemote},state) end
                or jackEmployee and function() EmployeeRenderer.draw(jackEmployee,characters) end
                or localJackOperator and drawPlayer or nil
            if math.sin(pose.heading)>=0 and operator then operator() end
            drawPalletJack(assets,state)
            if math.sin(pose.heading)<0 and operator then operator() end
        end}
    end
    for _,p in ipairs(remotePlayers or {}) do if Rooms.sameScene(p,world.player) then
        if p~=jackRemote then
            visible[p.character]=true
            actors[#actors+1]={y=p.y,draw=function() Avatar.draw(characters,{p},state) end}
        end
    end end
    for _,item in ipairs(require("src.pallet_logistics").physicalPallets(state)) do
        if item.pallet.world and (item.pallet.world.sceneId or "warehouse")==sceneId
            and (not jack or item.pallet.id~=jack.carriedPalletId) then
            actors[#actors+1]={y=item.y,draw=function() drawPallet(assets,item) end}
        end
    end
    characters.retainCharacters(visible,true)
    table.sort(actors,function(a,b) return a.y<b.y end)
    Beacon.drawUnderlay(world.getInteraction(),world.player.interactionClock,{})
    for _,actor in ipairs(actors) do actor.draw() end
    if Rooms.definition(state,sceneId)=="breakroom" and Games.owns(state,sceneId,"basketball") then
        for _,record in ipairs(require("src.basketball").renderRecords(state)) do
            if record.bayId==sceneId then
                love.graphics.setColor(.02,.04,.05,.82)
                love.graphics.rectangle("fill",610,86,330,37,5)
                love.graphics.setColor(.98,.85,.4,1)
                love.graphics.print(record.contestPhase and
                    ("BASKETBALL  "..record.leftScore.." : "..record.rightScore..
                        "  /  "..record.contestPhase:upper())
                    or ("BASKETBALL  /  STREAK "..record.streak),622,97)
                break
            end
        end
    end
    Beacon.drawOverlay(world.getInteraction(),world.player.interactionClock,{})
    local stage=Rooms.constructionStage(state,sceneId)
    love.graphics.setColor(.02,.035,.04,.90);love.graphics.rectangle("fill",12,80,310,stage and 72 or 52,5)
    love.graphics.setColor(.96,.92,.78,1);love.graphics.print(Rooms.name(state,sceneId),24,90)
    love.graphics.setColor(.76,.85,.86,1)
    if stage then
        love.graphics.print("Construction stage "..stage.." of 4 - room open",24,111)
        love.graphics.print("Use the rear-left door to return",24,132)
    else
        love.graphics.print("Use the rear-left door to return",24,111)
    end
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
