-- Registered authored construction views for all room choices and bay
-- orientations. Atlas crops remain source images; no module scenery is drawn
-- from placeholder geometry.
local Presentation={}
local ROOT="assets/source/warehouse-expansion-v1/"
local STORAGE_ROOT=ROOT.."construction/"
local ROOM_ROOT=ROOT.."rooms/"
local BAY_IDS={front_left=true,front_right=true}
local OPTION_IDS={floor=true,storage=true,breakroom=true}
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function storageEntry(bayId,stage)
    local right=bayId=="front_right"
    return {path=STORAGE_ROOT.."left-storage-stage-"..stage..".png",
        stage=stage,bayId=bayId,optionId="storage",approved=false,includesFloor=false,
        mirrorX=right,registration={textureWidth=1536,textureHeight=1024,
            source={x=0,y=0,width=1536,height=1024},
            groundAnchor=stage==1 and {x=155,y=350} or {x=164,y=492},
            worldX=right and 930 or 30,worldY=467,scale=0.27,depthY=647}}
end
local function atlasEntry(bayId,optionId,stage)
    local right=bayId=="front_right"
    local floor=optionId=="floor"
    local relative=floor and "floor-construction-atlas-v2-clean.png" or "breakroom-construction-atlas-v1.png"
    local sourceX=(stage==2 or stage==4) and 768 or 0
    local sourceY=(stage==3 or stage==4) and 512 or 0
    local anchorY=(stage<=2) and 480 or 445
    return {path=ROOM_ROOT..relative,stage=stage,bayId=bayId,optionId=optionId,
        approved=false,includesFloor=true,mirrorX=right,
        registration={textureWidth=1536,textureHeight=1024,
            source={x=sourceX,y=sourceY,width=768,height=512},
            groundAnchor={x=730,y=anchorY},worldX=right and 581 or 379,
            worldY=647,scale=0.49,depthY=647}}
end
local catalog={}
for _,bayId in ipairs({"front_left","front_right"}) do
    catalog[bayId]={floor={},storage={},breakroom={}}
    for stage=1,4 do
        catalog[bayId].storage[stage]=storageEntry(bayId,stage)
        catalog[bayId].floor[stage]=atlasEntry(bayId,"floor",stage)
        catalog[bayId].breakroom[stage]=atlasEntry(bayId,"breakroom",stage)
    end
end

function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry)~="table" or type(entry.path)~="string" or entry.path==""
        or not BAY_IDS[entry.bayId] or not OPTION_IDS[entry.optionId]
        or type(entry.approved)~="boolean" or type(entry.includesFloor)~="boolean"
        or (entry.mirrorX~=nil and type(entry.mirrorX)~="boolean")
        or not finite(entry.stage) or entry.stage~=math.floor(entry.stage) or entry.stage<1 or entry.stage>4 then
        return false,"invalid_construction_sprite"
    end
    local r=entry.registration
    if type(r)~="table" then return false,"construction_sprite_not_registered" end
    local source,anchor=r.source,r.groundAnchor
    if not finite(r.textureWidth) or not finite(r.textureHeight) or r.textureWidth<=0 or r.textureHeight<=0
        or type(source)~="table" or type(anchor)~="table" or not finite(source.x) or not finite(source.y)
        or not finite(source.width) or not finite(source.height) or not finite(anchor.x) or not finite(anchor.y)
        or source.x<0 or source.y<0 or source.width<=0 or source.height<=0
        or source.x+source.width>r.textureWidth or source.y+source.height>r.textureHeight
        or anchor.x<0 or anchor.y<0 or anchor.x>source.width or anchor.y>source.height
        or not finite(r.worldX) or not finite(r.worldY) or not finite(r.scale) or r.scale<=0 or r.scale>4
        or not finite(r.depthY) then return false,"invalid_construction_registration" end
    return true
end

function Presentation.plan(state,bayId,options)
    options=type(options)=="table" and options or {}
    local warehouse=type(state)=="table" and state.warehouse
    if type(warehouse)~="table" or type(warehouse.bays)~="table" or type(warehouse.projects)~="table" then
        return nil,"not_building"
    end
    local bay=warehouse.bays[bayId]
    if type(bay)~="table" or bay.status~="building" or not OPTION_IDS[bay.optionId] then return nil,"not_building" end
    local project
    for _,candidate in ipairs(warehouse.projects) do
        if type(candidate)=="table" and candidate.id==bay.projectId and candidate.bayId==bayId then project=candidate;break end
    end
    if not project or project.id~=warehouse.activeProjectId or project.phase~="building"
        or project.optionId~=bay.optionId or not finite(project.stage)
        or project.stage~=math.floor(project.stage) or project.stage<1 or project.stage>4 then
        return nil,"invalid_building_project"
    end
    local sourceCatalog=type(options.catalog)=="table" and options.catalog or catalog
    local bayCatalog=sourceCatalog[bayId]
    local optionCatalog=type(bayCatalog)=="table" and bayCatalog[project.optionId]
    local entry=type(optionCatalog)=="table" and optionCatalog[project.stage]
    local valid,code=Presentation.validateEntry(entry)
    if not valid then return nil,code end
    if entry.stage~=project.stage or entry.bayId~=bayId or entry.optionId~=project.optionId then
        return nil,"construction_stage_mismatch"
    end
    if not entry.approved and options.review~=true then return nil,"art_not_approved" end
    local r=entry.registration
    return {path=entry.path,bayId=bayId,optionId=project.optionId,stage=project.stage,projectId=project.id,
        source=copy(r.source),textureWidth=r.textureWidth,textureHeight=r.textureHeight,
        -- Keep the authored ground anchor in source coordinates when the
        -- draw is flipped. The negative x scale mirrors the entire source
        -- crop around that anchor; pre-flipping the origin a second time
        -- moves right-bay construction back over the left bay.
        originX=r.groundAnchor.x,
        originY=r.groundAnchor.y,x=r.worldX,y=r.worldY,scale=r.scale,mirrorX=entry.mirrorX==true,
        depthY=r.depthY,includesFloor=entry.includesFloor,approved=entry.approved,
        review=options.review==true,paused=project.pausedAtHours~=nil}
end

function Presentation.draw(state,bayId,getImage,options,graphics)
    local plan,code=Presentation.plan(state,bayId,options)
    if not plan then return false,code end
    if type(getImage)~="function" then return false,"image_provider_required" end
    local loaded,image=pcall(getImage,plan.path)
    if not loaded or not image or type(image.getDimensions)~="function" then return false,"image_unavailable" end
    local width,height=image:getDimensions()
    if width~=plan.textureWidth or height~=plan.textureHeight then return false,"image_dimensions" end
    graphics=graphics or (love and love.graphics)
    if not graphics then return false,"graphics_unavailable" end
    local r=plan.source
    local quad=graphics.newQuad(r.x,r.y,r.width,r.height,width,height)
    graphics.push("all")
    local okay,drawError=pcall(function()
        graphics.setColor(1,1,1,1)
        graphics.draw(image,quad,plan.x,plan.y,0,plan.scale*(plan.mirrorX and -1 or 1),
            plan.scale,plan.originX,plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not okay then return false,drawError end
    return true,plan
end
return Presentation
