-- Reviewed source registrations, not production-art approval. These sheets
-- are irregularly spaced: equal-width slicing severs tools and tails.
local Presentation={ BODY_WORLD_HEIGHT=76.8 }
local ROOT="assets/source/warehouse-expansion-v1/"
local tools={"concrete","hammer","drill","paint"}
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function frame(x,y,w,h,anchorX,anchorY,sourcePose)
    return {source={x=x,y=y,width=w,height=h},footAnchor={x=anchorX-x,y=anchorY-y},sourcePose=sourcePose}
end
local ATLAS=ROOT.."mechanic-work-atlas-v2.png"
local function sheet(bodyHeight,frames,issues)
    return {path=ATLAS,width=1254,height=1254,bodyReferenceHeight=bodyHeight,
        approved=false,usable=true,fps=4,frames=frames,sequence={1,2,3,4},issues=issues or {"minor_alpha_fringe"}}
end
local catalog={
    -- Body reference is the standing character, not the bounding box of a
    -- raised tool; concrete crouching deliberately remains shorter.
    concrete=sheet(277,{
        frame(42,80,232,232,176,305,1),frame(336,91,264,223,478,305,2),
        frame(640,108,294,218,792,305,3),frame(967,78,229,234,1105,305,4)},
        {"minor_alpha_fringe","column2_vertical_clearance_is_tight"}),
    -- Raised hammer crosses the nominal 320px row line. Individual crops
    -- preserve its complete silhouette; equal 4x4 atlas cells would clip it.
    hammer=sheet(277,{
        frame(43,344,222,299,181,631,1),frame(368,314,232,335,506,632,2),
        frame(650,381,290,263,790,631,3),frame(971,347,238,303,1113,631,4)}),
    drill=sheet(263,{
        frame(43,654,234,285,183,926,1),frame(347,654,285,280,485,927,2),
        frame(652,668,306,271,787,926,3),frame(977,658,237,281,1113,927,4)},
        {"minor_alpha_fringe","column2_vertical_clearance_is_tight"}),
    paint=sheet(279,{
        frame(45,948,281,299,180,1236,1),frame(352,934,249,313,484,1237,2),
        frame(663,959,295,288,803,1236,3),frame(972,968,261,279,1112,1237,4)}),
}

function Presentation.reviewCatalog() return copy(catalog) end

function Presentation.activeProject(worker,state)
    if type(worker)~="table" or worker.phase~="working" or worker.moving
        or not finite(worker.x) or not finite(worker.y) then return nil end
    local warehouse=type(state)=="table" and state.warehouse
    if type(warehouse)~="table" or warehouse.activeProjectId~=worker.projectId or type(warehouse.projects)~="table" then return nil end
    for _,project in ipairs(warehouse.projects) do
        if type(project)=="table" and project.id==worker.projectId and project.bayId==worker.bayId and project.phase=="building"
            and not project.pausedAtHours and finite(project.stage) and tools[project.stage] then return project end
    end
end

function Presentation.validateSheet(sheet)
    if type(sheet)~="table" or type(sheet.path)~="string" or sheet.path==""
        or not finite(sheet.width) or not finite(sheet.height) or sheet.width<=0 or sheet.height<=0
        or not finite(sheet.bodyReferenceHeight) or sheet.bodyReferenceHeight<=0
        or not finite(sheet.fps) or sheet.fps<=0 or sheet.fps>24
        or type(sheet.approved)~="boolean" or type(sheet.frames)~="table" or #sheet.frames<2
        or type(sheet.sequence)~="table" or #sheet.sequence<2 then return false,"incomplete_work_art" end
    for _,pose in ipairs(sheet.frames) do
        local r,a=pose.source,pose.footAnchor
        if type(r)~="table" or type(a)~="table" or not finite(r.x) or not finite(r.y)
            or not finite(r.width) or not finite(r.height) or not finite(a.x) or not finite(a.y)
            or r.x<0 or r.y<0 or r.width<=0 or r.height<=0
            or r.x+r.width>sheet.width or r.y+r.height>sheet.height
            or a.x<0 or a.y<0 or a.x>r.width or a.y>r.height then return false,"invalid_work_registration" end
    end
    for _,index in ipairs(sheet.sequence) do
        if not finite(index) or index~=math.floor(index) or not sheet.frames[index] then return false,"invalid_work_sequence" end
    end
    return true
end

function Presentation.plan(worker,state,options)
    options=type(options)=="table" and options or {}
    local project=Presentation.activeProject(worker,state)
    if not project then return nil,"not_actively_working" end
    local tool=tools[project.stage]
    local sheets=type(options.catalog)=="table" and options.catalog or catalog
    local sheet=sheets[tool]
    local valid,code=Presentation.validateSheet(sheet)
    if not valid then return nil,code end
    if sheet.usable==false then return nil,"work_art_needs_repair" end
    if not sheet.approved and options.review~=true then return nil,"art_not_approved" end
    local elapsed=worker.workStage==project.stage and finite(worker.workTime) and math.max(0,worker.workTime) or 0
    local sequenceIndex=math.floor(elapsed*sheet.fps)%#sheet.sequence+1
    local frameIndex=sheet.sequence[sequenceIndex]
    local pose=sheet.frames[frameIndex]
    return {tool=tool,stage=project.stage,path=sheet.path,frameIndex=frameIndex,sequenceIndex=sequenceIndex,
        source=copy(pose.source),textureWidth=sheet.width,textureHeight=sheet.height,
        originX=pose.footAnchor.x,originY=pose.footAnchor.y,
        x=worker.x,y=worker.y,scale=Presentation.BODY_WORLD_HEIGHT/sheet.bodyReferenceHeight,
        approved=sheet.approved,review=options.review==true,issues=copy(sheet.issues)}
end

function Presentation.draw(worker,state,getImage,options,graphics)
    local plan,code=Presentation.plan(worker,state,options)
    if not plan then return false,code end
    if type(getImage)~="function" then return false,"image_provider_required" end
    local image=getImage(plan.path)
    if not image or type(image.getDimensions)~="function" then return false,"image_unavailable" end
    local width,height=image:getDimensions()
    if width~=plan.textureWidth or height~=plan.textureHeight then return false,"image_dimensions" end
    graphics=graphics or (love and love.graphics)
    if not graphics then return false,"graphics_unavailable" end
    local r=plan.source
    local quad=graphics.newQuad(r.x,r.y,r.width,r.height,width,height)
    graphics.push("all")
    local success,drawError=pcall(function()
        graphics.setColor(1,1,1,1)
        graphics.draw(image,quad,plan.x,plan.y,0,plan.scale,plan.scale,plan.originX,plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not success then return false,drawError end
    return true,plan
end
return Presentation
