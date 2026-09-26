-- The first playable extension uses existing registered imagery, not a scaled
-- replacement of the shop. This projection is explicitly interim world art;
-- the approved first-person shelf image remains unchanged on disk.
local Layout = require("src.warehouse_layout")
local Storage = require("src.pallet_storage")
local PalletState = require("src.pallet_state")
local ForkliftPresentation = require("src.forklift_presentation")
local ForkliftLayeredPresentation = require("src.forklift_layered_presentation")
local MechanicWorkPresentation = require("src.mechanic_work_presentation")
local ConstructionPresentation = require("src.warehouse_construction_presentation")
local ModulePresentation = require("src.warehouse_module_presentation")
local RackPresentation = require("src.warehouse_rack_presentation")
local Config = require("src.config")
local Renderer = {}
local meshes, rackImage = {}, nil
local sourceImages, sourceQuads = {}, {}
local constructionIssues={}
local constructionImages={}
local ROOT="assets/source/warehouse-expansion-v1/"
local RACK_PATH="assets/source/warehouse-expansion-v1/rack-front-2x5-approved.png"
local DIRECTIONS={northwest=1,north=2,northeast=3,east=4,southeast=5,south=6,southwest=7,west=8}
local function sourceImage(path)
    if sourceImages[path]==false then return nil end
    if not sourceImages[path] then
        local okay,image=pcall(love.graphics.newImage,path)
        sourceImages[path]=okay and image or false
        if okay then image:setFilter("linear","linear") end
    end
    return sourceImages[path] or nil
end
local function sourceQuad(path,index,width,height)
    local key=path..":"..index
    if not sourceQuads[key] then
        local image=sourceImage(path)
        if not image then return nil end
        local iw,ih=image:getDimensions()
        sourceQuads[key]=love.graphics.newQuad((index-1)*width,0,width,height,iw,ih)
    end
    return sourceQuads[key]
end
local function releaseConstructionImage(bayId)
    local current=constructionImages[bayId]
    if current and current.image and current.image.release then current.image:release() end
    constructionImages[bayId]=nil
end
local function constructionImage(bayId,path)
    local current=constructionImages[bayId]
    if not current or current.path~=path then
        releaseConstructionImage(bayId)
        local okay,image=pcall(love.graphics.newImage,path)
        current={path=path,image=okay and image or false}
        constructionImages[bayId]=current
        if okay then image:setFilter("linear","linear") end
    end
    return current.image or nil
end

local function mesh(key,vertices,texture)
    if not meshes[key] then meshes[key]=love.graphics.newMesh(vertices,"fan","static") end
    meshes[key]:setTexture(texture)
    return meshes[key]
end
local function flat(polygon)
    local result={}
    for _, point in ipairs(polygon) do result[#result+1]=point.x; result[#result+1]=point.y end
    return result
end
local function loadRack()
    if rackImage==false then return nil end
    if not rackImage then
        local okay,value=pcall(love.graphics.newImage,RACK_PATH)
        rackImage=okay and value or false
        if rackImage then rackImage:setFilter("linear","linear") end
    end
    return rackImage or nil
end
local function drawFloor(assets,bay,stage,complete)
    local background=assets.get("warehouse")
    if background then
        -- Sample the unobstructed existing concrete floor, preserving its
        -- material, light and tile frequency without modifying bitmap assets.
        local samples={{330,355},{650,505},{330,505}}
        local vertices={}
        for index,point in ipairs(bay.walkPolygon) do
            vertices[index]={point.x,point.y,samples[index][1]/960,samples[index][2]/678,1,1,1,1}
        end
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(mesh("floor_"..bay.id,vertices,background))
    else
        -- Construction may use this existing image as a floor underlay, but
        -- never substitutes a flat colored shape when that image is absent.
        if not complete then return false,"floor_image_unavailable" end
        love.graphics.setColor(0.34,0.31,0.26,1)
        love.graphics.polygon("fill",unpack(flat(bay.walkPolygon)))
    end
    if not complete then return true end
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.18,0.17,0.15,1)
    local polygon=bay.polygon
    love.graphics.line(polygon[2].x,polygon[2].y,polygon[3].x,polygon[3].y,polygon[1].x,polygon[1].y)
    love.graphics.setLineWidth(1)
end
function Renderer.constructionPlan(state,bayId)
    return ConstructionPresentation.plan(state,bayId,
        {review=Config.warehouse and Config.warehouse.provisionalArt==true})
end
function Renderer.constructionIssue(bayId) return constructionIssues[bayId] end
local function drawConstruction(bay,stage,state)
    local drawn,reason=ConstructionPresentation.draw(state,bay.id,function(path) return constructionImage(bay.id,path) end,
        {review=Config.warehouse and Config.warehouse.provisionalArt==true})
    constructionIssues[bay.id]=not drawn and reason or nil
    -- Keep progress legible while the selected module is shown as a site
    -- preview or is intentionally an open-floor build with no room sprite.
    local x,y=bay.approach.x-92,bay.approach.y+40
    love.graphics.setColor(0.035,0.035,0.03,0.91)
    love.graphics.rectangle("fill",x,y,172,24,3,3)
    love.graphics.setColor(1,0.77,0.29,1)
    love.graphics.printf("BUILDING  "..stage.." / 4",x,y+5,172,"center")
    return drawn
end
function Renderer.drawFloors(assets,state)
    for _,id in ipairs(Layout.BAY_IDS) do
        local bay,status=Layout.bay(id),Layout.bayState(state,id)
        if status and status.status=="complete" then drawFloor(assets,bay,4,true)
        elseif status and status.status=="building" then
            drawFloor(assets,bay,4,false)
        end
    end
end
local function drawRackColumn(bay,column,alpha)
    local image=loadRack()
    if not image then return end
    alpha=type(alpha)=="number" and math.max(0,math.min(1,alpha)) or 1
    local first,last=(column-1)/5,column/5
    local function point(t,height)
        return bay.rackStart.x+(bay.rackEnd.x-bay.rackStart.x)*t,
            bay.rackStart.y+(bay.rackEnd.y-bay.rackStart.y)*t-height
    end
    local ax,ay=point(first,bay.rackHeight)
    local bx,by=point(last,bay.rackHeight)
    local cx,cy=point(last,0)
    local dx,dy=point(first,0)
    local u0,u1=(60+1420*first)/1536,(60+1420*last)/1536
    local vertices={{ax,ay,u0,155/1024,1,1,1,1},{bx,by,u1,155/1024,1,1,1,1},
        {cx,cy,u1,712/1024,1,1,1,1},{dx,dy,u0,712/1024,1,1,1,1}}
    love.graphics.setColor(1,1,1,alpha)
    love.graphics.draw(mesh("rack_"..bay.id.."_"..column,vertices,image))
end
local function drawWorldRack(state,bayId,bay,includeBuilding)
    local options={review=Config.warehouse and Config.warehouse.provisionalArt==true,
        includeBuilding=includeBuilding==true}
    local drawn=RackPresentation.draw(state,bayId,sourceImage,options)
    if drawn then return true end
    for column=1,5 do drawRackColumn(bay,column,includeBuilding and 0.55 or 1) end
    return false
end
function Renderer.addActors(actors,assets,state,drawPallet)
    for _,id in ipairs(Layout.BAY_IDS) do
        local bay,status=Layout.bay(id),Layout.bayState(state,id)
        if not status or status.status~="building" then
            constructionIssues[id]=nil
            releaseConstructionImage(id)
        end
        if status and status.status=="building" then
            local project=Layout.project(state,id)
            local stage=project and project.stage or 1
            local plan=Renderer.constructionPlan(state,id)
            -- One complete authored module is sorted at its front ground
            -- anchor. The builder remains sorted by his independent feet.
            local depth=plan and plan.depthY or math.max(bay.polygon[1].y,bay.polygon[2].y,bay.polygon[3].y)
            actors[#actors+1]={y=depth,layer=1,draw=function() drawConstruction(bay,stage,state) end}
            if status.optionId=="breakroom" and not plan then
                actors[#actors+1]={y=bay.polygon[3].y,layer=-2,draw=function()
                    ModulePresentation.draw(state,id,sourceImage,
                        {review=Config.warehouse and Config.warehouse.provisionalArt==true,includeBuilding=true})
                end}
            elseif status.optionId=="storage" and not plan then
                local rackPlan=RackPresentation.plan(state,id,{review=true,includeBuilding=true})
                local rackDepth=rackPlan and rackPlan.depthY or bay.rackStart.y
                actors[#actors+1]={y=rackDepth,layer=-2,draw=function()
                    drawWorldRack(state,id,bay,true)
                end}
            end
        elseif status and status.status=="complete" and status.optionId=="storage" then
            local rackPlan=RackPresentation.plan(state,id,{review=Config.warehouse and Config.warehouse.provisionalArt==true})
            local rackDepth=rackPlan and rackPlan.depthY or bay.rackStart.y
            actors[#actors+1]={y=rackDepth,layer=-2,draw=function()
                drawWorldRack(state,id,bay,false)
            end}
            local slots=Storage.slots(state,bay.rackId)
            for column=1,5 do
                local col=column
                for row=1,2 do
                    local r=row
                    local item=slots[r][col] and Storage.find(state,slots[r][col])
                    if item and drawPallet then
                        local point=rackPlan and RackPresentation.slotPoint(rackPlan,r,col)
                            or Layout.rackPoint(id,r,col)
                        local stock=item
                        actors[#actors+1]={y=point.groundY,layer=-1,draw=function()
                            drawPallet(assets,{pallet=stock.pallet,job=stock.job,vendor=stock.vendor,
                                x=point.x,y=point.y})
                        end}
                    end
                end
            end
        elseif status and status.status=="complete" and status.optionId=="breakroom" then
            actors[#actors+1]={y=bay.polygon[3].y,layer=-2,draw=function()
                ModulePresentation.draw(state,id,sourceImage,
                    {review=Config.warehouse and Config.warehouse.provisionalArt==true})
            end}
        end
    end
    -- A two-high stack is still one canonical pallet per level, never an
    -- inventory copy. Its upper pallet occludes actors at the base's depth.
    for _,item in ipairs(PalletState.items(state)) do
        if item.pallet.location=="stacked" and item.pallet.storage and drawPallet then
            local support=Storage.find(state,item.pallet.storage.supportPalletId)
            local point=support and support.pallet.world
            if point then
                local upper=item
                actors[#actors+1]={y=point.y+0.1,layer=1,draw=function()
                    drawPallet(assets,{pallet=upper.pallet,job=upper.job,vendor=upper.vendor,
                        x=point.x,y=point.y-39})
                end}
            end
        end
    end
end

function Renderer.drawConstructionWorker(worker,state)
    if not worker or worker.phase=="hidden" or worker.phase=="exited" then return end
    love.graphics.setColor(0.02,0.02,0.02,0.2)
    love.graphics.ellipse("fill",worker.x,worker.y+1,14,5)
    local review=Config.warehouse and Config.warehouse.provisionalArt==true
    local working,plan=MechanicWorkPresentation.draw(worker,state,sourceImage,{review=review})
    if not working then
        local direction=DIRECTIONS[worker.direction] and worker.direction or "south"
        local action=worker.moving and "walk" or "idle"
        local path=ROOT.."mechanic-raccoon/"..action..(direction=="east" and "" or "_"..direction)..".png"
        local image=sourceImage(path)
        if not image then return end
        local frame=worker.moving and (math.floor((worker.animationDistance or 0)/13)%8+1)
            or (math.floor(math.max(0,worker.idleTime or 0)*0.65)%2+1)
        local quad=sourceQuad(path,frame,512,512)
        if not quad then return end
        love.graphics.setColor(1,1,1,1)
        local scale=76.8/385
        love.graphics.draw(image,quad,worker.x,worker.y,0,scale,scale,256,458)
    end
    if worker.phase=="working" then
        local active=MechanicWorkPresentation.activeProject(worker,state)
        local label=working and string.upper(plan.tool) or (active and "BUILDING" or "PAUSED")
        love.graphics.setColor(0.06,0.055,0.045,0.9)
        love.graphics.rectangle("fill",worker.x-35,worker.y+5,70,16,3,3)
        love.graphics.setColor(1,0.8,0.3,1)
        love.graphics.printf(label,worker.x-35,worker.y+7,70,"center")
    end
end

function Renderer.forkliftScales()
    local options=Config.forklift or {}
    local multiplier=options.visualScaleMultiplier or 1
    return (options.drawScale or 0.22)*multiplier,
        (options.parkedDrawScale or 0.25)*multiplier,multiplier
end
function Renderer.forkliftPlan(vehicle)
    if not vehicle or not vehicle.owned then return nil end
    -- This explicit development switch does not approve source imagery or
    -- change the production presentation gate. Both driver and empty-seat
    -- strips retain the actual fork height and share the same body scale.
    if Config.warehouse and Config.warehouse.provisionalArt then
        local scale=Renderer.forkliftScales()
        return ForkliftPresentation.plan(vehicle,{review=true,scale=scale})
    end
end
function Renderer.layeredForkliftPlan(vehicle)
    if not vehicle or not vehicle.owned or not (Config.warehouse and Config.warehouse.provisionalArt) then
        return nil
    end
    local scale=Renderer.forkliftScales()
    return ForkliftLayeredPresentation.plan(vehicle,{review=true,scale=scale})
end
function Renderer.parkedForkliftPlan(vehicle,width,height)
    if not vehicle or not vehicle.owned then return nil end
    local index=DIRECTIONS[vehicle.direction] or 1
    local _,scale,multiplier=Renderer.forkliftScales()
    local cellWidth,cellHeight=width/4,height/2
    return {directionFrame=index,x=vehicle.x,y=vehicle.y,scale=scale,
        originX=cellWidth/2,originY=cellHeight*0.91,
        source={x=((index-1)%4)*cellWidth,y=math.floor((index-1)/4)*cellHeight,
            width=cellWidth,height=cellHeight},
        loadX=vehicle.x,loadY=vehicle.y-(10+(vehicle.forkHeight or 0)*58)*multiplier}
end
function Renderer.drawForklift(assets,state,drawPallet)
    local vehicle=state and state.forklift
    if not vehicle or not vehicle.owned then return end
    local layeredPlan=Renderer.layeredForkliftPlan(vehicle)
    local plan=layeredPlan or Renderer.forkliftPlan(vehicle)
    local operatingScale,_,multiplier=Renderer.forkliftScales()
    local drawn=false
    local loadX,loadY=vehicle.x,vehicle.y-(10+(vehicle.forkHeight or 0)*58)*multiplier
    if plan then loadX,loadY=plan.loadX,plan.loadY end
    local item=vehicle.carriedPalletId and drawPallet and Storage.find(state,vehicle.carriedPalletId)
    local function drawLoad()
        if item then drawPallet(assets,{pallet=item.pallet,job=item.job,vendor=item.vendor,
            x=loadX,y=loadY,hideWorldLabel=true}) end
    end
    -- The full-body rear art covers its load. Layered rear diagonals put the
    -- pallet over the moving tines so its contact stays visible.
    local loadBehind=plan and (vehicle.direction=="north"
        or not layeredPlan and (vehicle.direction=="northwest" or vehicle.direction=="northeast"))
    if loadBehind then drawLoad() end
    if layeredPlan then drawn=ForkliftLayeredPresentation.draw(vehicle,sourceImage,
        {review=true,scale=operatingScale}) end
    if not drawn then
        plan=Renderer.forkliftPlan(vehicle)
        if plan then
            loadX,loadY=plan.loadX,plan.loadY
            if layeredPlan and (vehicle.direction=="northwest" or vehicle.direction=="northeast") then
                drawLoad()
                loadBehind=true
            end
            drawn=ForkliftPresentation.draw(vehicle,sourceImage,
                {review=true,scale=operatingScale,edgeCleanup=true})
        end
    end
    if not drawn then
        local path=ROOT.."forklift-eight-directions-unmanned-v1.png"
        local image=sourceImage(path)
        if image then
            local width,height=image:getDimensions()
            local parked=Renderer.parkedForkliftPlan(vehicle,width,height)
            local source=parked.source
            local key=path..":"..parked.directionFrame
            if not sourceQuads[key] then
                sourceQuads[key]=love.graphics.newQuad(source.x,source.y,source.width,source.height,width,height)
            end
            love.graphics.setColor(1,1,1,1)
            love.graphics.draw(image,sourceQuads[key],parked.x,parked.y,0,parked.scale,parked.scale,
                parked.originX,parked.originY)
            loadX,loadY=parked.loadX,parked.loadY
        end
    end
    if not loadBehind then drawLoad() end
end
function Renderer.drawVehicleStatus(state)
    local vehicle=state and state.forklift
    if not vehicle or not vehicle.owned then return end
    local load=vehicle.carriedPalletId and Storage.find(state,vehicle.carriedPalletId)
    local label=load and load.pallet and load.pallet.number and "P"..tostring(load.pallet.number)
        or vehicle.carriedPalletId and "LOAD"
    local text=string.format("FORKS %d%%",math.floor((vehicle.forkHeight or 0)*100+0.5))
    if label then text=text.."  "..label end
    local width=math.max(96,love.graphics.getFont():getWidth(text)+12)
    love.graphics.setColor(0.03,0.035,0.035,0.85)
    love.graphics.rectangle("fill",vehicle.x-width/2,vehicle.y+6,width,17,3,3)
    love.graphics.setColor(1,0.83,0.32,1)
    love.graphics.printf(text,vehicle.x-width/2,vehicle.y+8,width,"center")
end

function Renderer.drawDevelopmentNotice(state)
    local enabled=Config.warehouse and Config.warehouse.provisionalArt
    if not enabled or not state or not ((state.forklift and state.forklift.owned)
        or state.constructionWorker) then return end
    love.graphics.setColor(0.03,0.035,0.035,0.82)
    local text="Development artwork: forklift / worker"
    local width=love.graphics.getFont():getWidth(text)+10
    love.graphics.rectangle("fill",8,638,width,18,3,3)
    love.graphics.setColor(0.88,0.80,0.55,1)
    love.graphics.print(text,13,641)
end

return Renderer
