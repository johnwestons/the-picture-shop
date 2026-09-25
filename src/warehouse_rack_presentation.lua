-- Authored world-space rack, distinct from the first-person inventory backdrop.
-- A single native sprite transform is shared by its ten pallet anchors and
-- texture-derived foreground masks. No GUI texture projection or drawn rack art.
local Presentation={}
local PATH="assets/source/warehouse-expansion-v1/rack-world-left-v2.png"
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
local catalog={front_left={path=PATH,bayId="front_left",approved=false,registration=nil}}

function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry)~="table" or type(entry.path)~="string" or entry.path==""
        or entry.path:find("rack-front",1,true) or entry.bayId~="front_left"
        or type(entry.approved)~="boolean" then return false,"invalid_world_rack_sprite" end
    local r=entry.registration
    if type(r)~="table" then return false,"world_rack_not_registered" end
    if not finite(r.textureWidth) or not finite(r.textureHeight) or r.textureWidth<=0 or r.textureHeight<=0
        or not finite(r.x) or not finite(r.y) or not finite(r.scale) or r.scale<=0 or r.scale>4
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
    plan.path,plan.bayId,plan.approved,plan.review=entry.path,bayId,entry.approved,options.review==true
    return plan
end

function Presentation.sourceToWorld(plan,x,y)
    return plan.x+(x-plan.originX)*plan.scale,plan.y+(y-plan.originY)*plan.scale
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

function Presentation.drawBack(plan,getImage,graphics)
    local image,reason=imageFor(plan,getImage)
    if not image then return false,reason end
    graphics=graphics or (love and love.graphics)
    if not graphics then return false,"graphics_unavailable" end
    graphics.setColor(1,1,1,1)
    graphics.draw(image,plan.x,plan.y,0,plan.scale,plan.scale,plan.originX,plan.originY)
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
            -- These polygons only mask already-authored sprite pixels. They
            -- are never visible colored substitute beams or shelf geometry.
            graphics.polygon("fill",unpack(polygon))
        end
    end,"replace",1)
    graphics.setStencilTest("greater",0)
    graphics.setColor(1,1,1,1)
    graphics.draw(image,plan.x,plan.y,0,plan.scale,plan.scale,plan.originX,plan.originY)
    graphics.setStencilTest()
    graphics.pop()
    return true
end
return Presentation
