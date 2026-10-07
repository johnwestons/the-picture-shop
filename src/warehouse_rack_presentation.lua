-- Authored world-space rack, distinct from the first-person inventory art.
-- Both bays share one sprite; the right side mirrors its registration, slots,
-- and authored foreground mask around the right-bay anchor.
local Layout=require("src.warehouse_layout")
local Presentation={}
local PATH="assets/source/warehouse-expansion-v1/rack-world-left-v9-perspective-candidate.png"
-- Near-uniform registration of the redraw: the old rack was squeezed to
-- less than half this width. Source plate contacts were measured in RGBA.
local WIDTH,HEIGHT,ORIGIN_X,ORIGIN_Y,SCALE_X,SCALE_Y=1254,1254,59.1,475.5,272/958.4,191.35/695.8
local BAY_IDS={front_left=true,front_right=true}
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local function frontMask()
    local polygons={
        -- Authored front-face sections of the two straight orange shelf beams.
        {60,156,1018,852,1018,884,60,188},
        {60,405,1018,1111,1018,1145,60,439},
    }
    -- The six front uprights are painted over stored loads after their back
    -- faces and the canonical pallet sprites have been drawn.
    for _,x in ipairs({59,249,441,635,824,1018}) do
        polygons[#polygons+1]={x-14,20,x+14,20,x+14,1200,x-14,1200}
    end
    return polygons
end
local function registration(bayId)
    local bay=Layout.bay(bayId)
    local mirror=bayId=="front_right"
    local worldX=bay.rackGroundPosts[1].x
    local worldY=bay.rackGroundPosts[1].y
    local direction=mirror and -1 or 1
    local slots={{},{}}
    for row=1,2 do for column=1,5 do
        local point=Layout.rackPoint(bayId,row,column)
        local sourceX=ORIGIN_X+(point.x-worldX)/(SCALE_X*direction)
        local sourceY=ORIGIN_Y+(point.y-worldY)/SCALE_Y
        local groundY=ORIGIN_Y+(point.groundY-worldY)/SCALE_Y
        slots[row][column]={x=sourceX,y=sourceY,groundY=groundY}
    end end
    return {textureWidth=WIDTH,textureHeight=HEIGHT,x=worldX,y=worldY,
        originX=ORIGIN_X,originY=ORIGIN_Y,scale=SCALE_X,scaleX=SCALE_X,scaleY=SCALE_Y,
        depthY=bay.rackGroundPosts[6].y,
        mirrorX=mirror,slots=slots,frontPolygons=frontMask()}
end
local catalog={}
for _,bayId in ipairs({"front_left","front_right"}) do
    catalog[bayId]={path=PATH,bayId=bayId,approved=false,
        mirrorX=bayId=="front_right",registration=registration(bayId)}
end

function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry)~="table" or type(entry.path)~="string" or entry.path==""
        or entry.path:find("rack-front",1,true) or not BAY_IDS[entry.bayId]
        or type(entry.approved)~="boolean"
        or (entry.mirrorX~=nil and type(entry.mirrorX)~="boolean") then
        return false,"invalid_world_rack_sprite"
    end
    local r=entry.registration
    if type(r)~="table" then return false,"world_rack_not_registered" end
    if not finite(r.textureWidth) or not finite(r.textureHeight) or r.textureWidth<=0 or r.textureHeight<=0
        or not finite(r.x) or not finite(r.y) or not finite(r.scale) or r.scale<=0 or r.scale>4
        or (r.scaleX~=nil and (not finite(r.scaleX) or r.scaleX<=0 or r.scaleX>4))
        or (r.scaleY~=nil and (not finite(r.scaleY) or r.scaleY<=0 or r.scaleY>4))
        or not finite(r.originX) or not finite(r.originY) or not finite(r.depthY)
        or r.originX<0 or r.originX>r.textureWidth or r.originY<0 or r.originY>r.textureHeight
        or type(r.slots)~="table" or #r.slots~=2 or type(r.frontPolygons)~="table" then
        return false,"invalid_world_rack_registration"
    end
    for row=1,2 do
        if type(r.slots[row])~="table" or #r.slots[row]~=5 then return false,"world_rack_requires_ten_slots" end
        for column=1,5 do
            local p=r.slots[row][column]
            if type(p)~="table" or not finite(p.x) or not finite(p.y) or not finite(p.groundY)
                or p.x<0 or p.x>r.textureWidth or p.y<0 or p.y>r.textureHeight
                or p.groundY<0 or p.groundY>r.textureHeight then return false,"invalid_world_rack_slot" end
            if row==2 then
                local lower=r.slots[1][column]
                if p.x~=lower.x or p.groundY~=lower.groundY or p.y>=lower.y then
                    return false,"invalid_world_rack_upper_slot"
                end
            end
        end
    end
    for _,polygon in ipairs(r.frontPolygons) do
        if type(polygon)~="table" or #polygon<6 or #polygon%2~=0 then return false,"invalid_world_rack_foreground" end
        for index,value in ipairs(polygon) do
            if not finite(value) or value<0 or value>(index%2==1 and r.textureWidth or r.textureHeight) then
                return false,"invalid_world_rack_foreground"
            end
        end
    end
    return true
end

function Presentation.plan(state,bayId,options)
    options=type(options)=="table" and options or {}
    local bay=type(state)=="table" and state.warehouse and state.warehouse.bays and state.warehouse.bays[bayId]
    if not bay or bay.status~="complete" or bay.optionId~="storage" then return nil,"rack_not_complete" end
    local entry=(options.catalog or catalog)[bayId]
    local valid,code=Presentation.validateEntry(entry)
    if not valid then return nil,code end
    if not entry.approved and options.review~=true then return nil,"art_not_approved" end
    local plan=copy(entry.registration)
    plan.path,plan.bayId,plan.approved=entry.path,bayId,entry.approved
    plan.mirrorX=entry.mirrorX==true or plan.mirrorX==true
    plan.scaleX=entry.registration.scaleX or entry.registration.scale
    plan.scaleY=entry.registration.scaleY or entry.registration.scale
    plan.review=options.review==true
    return plan
end

function Presentation.sourceToWorld(plan,x,y)
    local direction=plan.mirrorX and -1 or 1
    local scaleX,scaleY=plan.scaleX or plan.scale,plan.scaleY or plan.scale
    return plan.x+(x-plan.originX)*scaleX*direction,
        plan.y+(y-plan.originY)*scaleY
end
function Presentation.slotPoint(plan,row,column)
    if not plan or (row~=1 and row~=2) or not finite(column) or column%1~=0 or column<1 or column>5 then return nil end
    local p=plan.slots[row][column]
    local x,y=Presentation.sourceToWorld(plan,p.x,p.y)
    local _,groundY=Presentation.sourceToWorld(plan,p.x,p.groundY)
    return {x=x,y=y,groundY=groundY,row=row,column=column}
end

local function imageFor(plan,getImage)
    if not plan or type(getImage)~="function" then return nil,"image_provider_required" end
    local okay,image=pcall(getImage,plan.path)
    if not okay or not image or type(image.getDimensions)~="function" then return nil,"image_unavailable" end
    local width,height=image:getDimensions()
    if width~=plan.textureWidth or height~=plan.textureHeight then return nil,"image_dimensions" end
    return image
end
local function drawImage(plan,image,graphics)
    graphics.push("all")
    graphics.setColor(1,1,1,1)
    local sx=(plan.scaleX or plan.scale)*(plan.mirrorX and -1 or 1)
    graphics.draw(image,plan.x,plan.y,0,sx,plan.scaleY or plan.scale,plan.originX,plan.originY)
    graphics.pop()
end
function Presentation.drawBack(plan,getImage,graphics)
    local image,reason=imageFor(plan,getImage)
    if not image then return false,reason end
    graphics=graphics or (love and love.graphics)
    if not graphics then return false,"graphics_unavailable" end
    drawImage(plan,image,graphics)
    return true
end
function Presentation.drawFront(plan,getImage,graphics)
    if not plan then return false,"plan_required" end
    if #plan.frontPolygons==0 then return true end
    local image,reason=imageFor(plan,getImage)
    if not image then return false,reason end
    graphics=graphics or (love and love.graphics)
    if not graphics then return false,"graphics_unavailable" end
    graphics.push("all")
    graphics.stencil(function()
        for _,source in ipairs(plan.frontPolygons) do
            local polygon={}
            for index=1,#source,2 do
                local x,y=Presentation.sourceToWorld(plan,source[index],source[index+1])
                polygon[#polygon+1]=x;polygon[#polygon+1]=y
            end
            graphics.polygon("fill",unpack(polygon))
        end
    end,"replace",1)
    graphics.setStencilTest("greater",0)
    drawImage(plan,image,graphics)
    graphics.setStencilTest()
    graphics.pop()
    return true
end
return Presentation
