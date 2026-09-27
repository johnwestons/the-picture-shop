-- Reviewed per-frame work registrations. These eight-pose atlases use a
-- regular 4x2 grid, but remain development art until visually approved.
local Presentation={ BODY_WORLD_HEIGHT=76.8 }
local ROOT="assets/source/warehouse-expansion-v1/"
local tools={"concrete","hammer","drill","paint"}
local edgeShader
local edgeShaderSource=[[
    extern vec2 sourceSize;
    extern vec4 sourceRect;

    vec4 premultipliedSample(Image texture, vec2 pixel) {
        vec4 sample = Texel(texture, (pixel + vec2(0.5)) / sourceSize);
        return vec4(sample.rgb * sample.a, sample.a);
    }

    vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screenCoords) {
        vec2 position = uv * sourceSize - vec2(0.5);
        vec2 first = clamp(floor(position), sourceRect.xy,
            sourceRect.xy + sourceRect.zw - vec2(1.0));
        vec2 second = clamp(floor(position) + vec2(1.0), sourceRect.xy,
            sourceRect.xy + sourceRect.zw - vec2(1.0));
        vec2 fraction = fract(position);
        vec4 top = mix(premultipliedSample(texture, first),
            premultipliedSample(texture, vec2(second.x, first.y)), fraction.x);
        vec4 bottom = mix(premultipliedSample(texture, vec2(first.x, second.y)),
            premultipliedSample(texture, second), fraction.x);
        vec4 result = mix(top, bottom, fraction.y);
        if (result.a <= 0.00001) return vec4(0.0);
        return vec4(result.rgb / result.a, result.a) * color;
    }
]]
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function frame(x,y,w,h,anchorX,anchorY,sourcePose)
    return {source={x=x,y=y,width=w,height=h},footAnchor={x=anchorX-x,y=anchorY-y},sourcePose=sourcePose}
end
local function cellFrame(index,anchorX,anchorY)
    local zero=index-1
    local x,y=(zero%4)*384,math.floor(zero/4)*512
    return frame(x,y,384,512,x+anchorX,y+anchorY,index)
end
local function sheet(tool,version,bodyHeight,anchors,issues)
    local frames={}
    for index,anchor in ipairs(anchors) do
        frames[index]=cellFrame(index,anchor[1],anchor[2])
    end
    local sequence={}
    for index=1,#frames do sequence[index]=index end
    return {path=ROOT.."mechanic-work-"..tool.."-"..version.."-candidate.png",
        width=1536,height=1024,bodyReferenceHeight=bodyHeight,approved=false,
        usable=true,fps=4,frames=frames,sequence=sequence,
        issues=issues or {"generated_development_art_requires_review"}}
end
local catalog={
    -- Scale uses body height, not the extended tool bounds. Each anchor stays
    -- on the planted stance while the arms, torso and tools travel.
    concrete=sheet("concrete","v3c",300,{
        {180,450},{180,450},{180,450},{180,450},
        {180,420},{180,420},{180,420},{180,420}},
        {"generated_development_art_requires_review","edge_clearance_below_32px"}),
    hammer=sheet("hammer","v3",322,{
        {205,465},{205,466},{205,466},{205,465},
        {205,433},{205,432},{205,433},{205,433}},
        {"generated_development_art_requires_review","raised_tool_changes_bounds"}),
    drill=sheet("drill","v3c",337,{
        {206,456},{198,457},{192,458},{190,458},
        {205,419},{200,419},{200,419},{199,419}},
        {"generated_development_art_requires_review","edge_clearance_below_32px"}),
    paint=sheet("paint","v3",320,{
        {206,459},{199,459},{194,459},{187,459},
        {206,425},{204,425},{207,425},{201,425}},
        {"generated_development_art_requires_review","raised_tool_changes_bounds"}),
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
    options=type(options)=="table" and options or {}
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
        if options.edgeCleanup and graphics.newShader and graphics.setShader then
            if edgeShader==nil then
                local created,shader=pcall(graphics.newShader,edgeShaderSource)
                edgeShader=created and shader or false
            end
            if edgeShader then
                edgeShader:send("sourceSize",{width,height})
                edgeShader:send("sourceRect",{r.x,r.y,r.width,r.height})
                graphics.setShader(edgeShader)
            end
        end
        graphics.setColor(1,1,1,1)
        graphics.draw(image,quad,plan.x,plan.y,0,plan.scale,plan.scale,plan.originX,plan.originY)
    end)
    graphics.pop()
    if quad.release then quad:release() end
    if not success then return false,drawError end
    return true,plan
end
return Presentation
