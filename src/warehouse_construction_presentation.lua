-- Construction progress is authored sprite art. This module only registers,
-- selects and draws existing images; it never invents environmental geometry.
local Presentation={}
local ROOT="assets/source/warehouse-expansion-v1/construction/"
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local catalog={front_left={}}
for stage=1,4 do
    catalog.front_left[stage]={path=ROOT.."left-storage-stage-"..stage..".png",
        stage=stage,bayId="front_left",optionId="storage",approved=false,includesFloor=true,
        -- Source dimensions, crop and floor-anchor registration are completed
        -- only after the actual generated sprite has been inspected.
        registration=nil}
end

function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry)~="table" or type(entry.path)~="string" or entry.path==""
        or entry.bayId~="front_left" or entry.optionId~="storage" or type(entry.approved)~="boolean"
        or type(entry.includesFloor)~="boolean"
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
    if type(bay)~="table" or bay.status~="building" or bay.optionId~="storage" then return nil,"not_building" end
    local project
    for _,candidate in ipairs(warehouse.projects) do
        if type(candidate)=="table" and candidate.id==bay.projectId and candidate.bayId==bayId then project=candidate;break end
    end
    if not project or project.id~=warehouse.activeProjectId or project.phase~="building" or project.optionId~="storage"
        or not finite(project.stage) or project.stage~=math.floor(project.stage) or project.stage<1 or project.stage>4 then
        return nil,"invalid_building_project"
    end
    local sourceCatalog=type(options.catalog)=="table" and options.catalog or catalog
    local bayCatalog=sourceCatalog[bayId]
    local entry=type(bayCatalog)=="table" and bayCatalog[project.stage]
    local valid,code=Presentation.validateEntry(entry)
    if not valid then return nil,code end
    if entry.stage~=project.stage or entry.bayId~=bayId then return nil,"construction_stage_mismatch" end
    if not entry.approved and options.review~=true then return nil,"art_not_approved" end
    local r=entry.registration
    return {path=entry.path,bayId=bayId,stage=project.stage,projectId=project.id,
        source=copy(r.source),textureWidth=r.textureWidth,textureHeight=r.textureHeight,
        originX=r.groundAnchor.x,originY=r.groundAnchor.y,x=r.worldX,y=r.worldY,scale=r.scale,
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
        graphics.draw(image,quad,plan.x,plan.y,0,plan.scale,plan.scale,plan.originX,plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not okay then return false,drawError end
    return true,plan
end
return Presentation
