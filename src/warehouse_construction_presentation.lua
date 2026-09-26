-- Construction progress is authored sprite art. This module only registers,
-- selects and draws existing images; it never invents environmental geometry.
local Presentation={}
local ROOT="assets/source/warehouse-expansion-v1/"
local ModulePresentation=require("src.warehouse_module_presentation")
local RackPresentation=require("src.warehouse_rack_presentation")
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function moduleRegistration(entry)
    local r=entry.registration
    return {textureWidth=r.textureWidth,textureHeight=r.textureHeight,source=copy(r.source),
        groundAnchor={x=r.originX,y=r.originY},worldX=r.x,worldY=r.y,scale=r.scale,depthY=r.depthY}
end
local function rackRegistration(entry)
    local r=entry.registration
    return {textureWidth=r.textureWidth,textureHeight=r.textureHeight,
        source={x=0,y=0,width=r.textureWidth,height=r.textureHeight},
        groundAnchor={x=r.originX,y=r.originY},worldX=r.x,worldY=r.y,scale=1,
        scaleX=r.scaleX,scaleY=r.scaleY,rotation=r.rotation,depthY=r.depthY}
end
local function stageEntry(path,bayId,optionId,stage,registration)
    return {path=path,stage=stage,bayId=bayId,optionId=optionId,approved=true,
        includesFloor=false,registration=copy(registration)}
end
local function makeCatalog()
    local result={front_left={storage={},breakroom={}},front_right={storage={},breakroom={}}}
    local modules=ModulePresentation.reviewCatalog()
    local racks=RackPresentation.reviewCatalog()
    local leftStorageRegistration={textureWidth=1536,textureHeight=1024,
        source={x=0,y=0,width=1536,height=1024},groundAnchor={x=100,y=970},
        worldX=177,worldY=647,scale=0.15,depthY=647}
    for stage=1,4 do
        local entry=stageEntry(ROOT.."modules/left-storage-stage-"..stage..".png",
            "front_left","storage",stage,leftStorageRegistration)
        result.front_left.storage[stage]=entry
        -- Keep the original review-catalog indexing for existing callers.
        result.front_left[stage]=entry

        local rack=rackRegistration(racks.front_right)
        local rackPath=stage<4 and ROOT.."modules/rack-right-stage-"..stage..".png"
            or racks.front_right.path
        result.front_right.storage[stage]=stageEntry(rackPath,"front_right","storage",stage,rack)

        for _,bayId in ipairs({"front_left","front_right"}) do
            local module=modules[bayId]
            local path=stage<4 and ROOT.."modules/breakroom-"
                ..(bayId=="front_left" and "left" or "right").."-stage-"..stage..".png"
                or module.path
            result[bayId].breakroom[stage]=stageEntry(path,bayId,"breakroom",stage,moduleRegistration(module))
        end
    end
    return result
end
local catalog=makeCatalog()

function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry)~="table" or type(entry.path)~="string" or entry.path==""
        or (entry.bayId~="front_left" and entry.bayId~="front_right")
        or (entry.optionId~="floor" and entry.optionId~="storage" and entry.optionId~="breakroom")
        or type(entry.approved)~="boolean"
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
        or (r.scaleX~=nil and (not finite(r.scaleX) or r.scaleX<=0 or r.scaleX>4))
        or (r.scaleY~=nil and (not finite(r.scaleY) or r.scaleY<=0 or r.scaleY>4))
        or (r.rotation~=nil and not finite(r.rotation))
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
    if type(bay)~="table" or bay.status~="building" then return nil,"not_building" end
    local project
    for _,candidate in ipairs(warehouse.projects) do
        if type(candidate)=="table" and candidate.id==bay.projectId and candidate.bayId==bayId then project=candidate;break end
    end
    if not project or project.id~=warehouse.activeProjectId or project.phase~="building" or project.optionId~=bay.optionId
        or not finite(project.stage) or project.stage~=math.floor(project.stage) or project.stage<1 or project.stage>4 then
        return nil,"invalid_building_project"
    end
    local sourceCatalog=type(options.catalog)=="table" and options.catalog or catalog
    local bayCatalog=sourceCatalog[bayId]
    local optionCatalog=type(bayCatalog)=="table" and bayCatalog[project.optionId]
    if type(optionCatalog)~="table" and project.optionId=="storage" then optionCatalog=bayCatalog end
    local entry=type(optionCatalog)=="table" and optionCatalog[project.stage]
    local valid,code=Presentation.validateEntry(entry)
    if not valid then return nil,code end
    if entry.stage~=project.stage or entry.bayId~=bayId or entry.optionId~=project.optionId then
        return nil,"construction_stage_mismatch"
    end
    if not entry.approved and options.review~=true then return nil,"art_not_approved" end
    local r=entry.registration
    return {path=entry.path,bayId=bayId,stage=project.stage,projectId=project.id,
        source=copy(r.source),textureWidth=r.textureWidth,textureHeight=r.textureHeight,
        originX=r.groundAnchor.x,originY=r.groundAnchor.y,x=r.worldX,y=r.worldY,scale=r.scale,
        scaleX=r.scaleX or r.scale,scaleY=r.scaleY or r.scale,rotation=r.rotation or 0,
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
        graphics.draw(image,quad,plan.x,plan.y,plan.rotation,plan.scaleX,plan.scaleY,plan.originX,plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not okay then return false,drawError end
    return true,plan
end
return Presentation
