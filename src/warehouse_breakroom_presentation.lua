-- Cutaway room shell and furnishings for the purchased employee breakroom.
-- The warehouse floor and collision mask remain owned by the bay layout.
local Layout=require("src.warehouse_layout")
local Presentation={}
local PATH="assets/source/warehouse-expansion-v1/rooms/breakroom-furnishings-v1.png"
local WIDTH,HEIGHT=1536,1024
local SCALE,ORIGIN_X,ORIGIN_Y=0.24,768,970
local catalog={}
for _,bayId in ipairs(Layout.BAY_IDS) do
    local bay=Layout.bay(bayId)
    local minX,maxX=math.huge,-math.huge
    for _,point in ipairs(bay.polygon) do minX=math.min(minX,point.x);maxX=math.max(maxX,point.x) end
    catalog[bayId]={path=PATH,bayId=bayId,approved=false,mirrorX=bayId=="front_right",
        registration={textureWidth=WIDTH,textureHeight=HEIGHT,
            x=(minX+maxX)/2,y=610,originX=ORIGIN_X,originY=ORIGIN_Y,
            scale=SCALE,depthY=610}}
end
local function copy(value)
    if type(value)~="table" then return value end
    local result={} for key,item in pairs(value) do result[key]=copy(item) end return result
end
local function finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end
function Presentation.reviewCatalog() return copy(catalog) end
function Presentation.validateEntry(entry)
    if type(entry)~="table" or type(entry.path)~="string" or entry.path==""
        or type(entry.bayId)~="string" or not Layout.bay(entry.bayId)
        or type(entry.approved)~="boolean" or type(entry.mirrorX)~="boolean" then
        return false,"invalid_breakroom_sprite"
    end
    local r=entry.registration
    if type(r)~="table" or not finite(r.textureWidth) or r.textureWidth~=WIDTH
        or not finite(r.textureHeight) or r.textureHeight~=HEIGHT
        or not finite(r.x) or not finite(r.y) or not finite(r.originX) or not finite(r.originY)
        or r.originX<0 or r.originX>WIDTH or r.originY<0 or r.originY>HEIGHT
        or not finite(r.scale) or r.scale<=0 or r.scale>4 or not finite(r.depthY) then
        return false,"invalid_breakroom_registration"
    end
    return true
end
function Presentation.plan(state,bayId,options)
    options=type(options)=="table" and options or {}
    local bay=type(state)=="table" and state.warehouse and state.warehouse.bays and state.warehouse.bays[bayId]
    if not bay or bay.status~="complete" or bay.optionId~="breakroom" then return nil,"breakroom_not_complete" end
    local entry=(options.catalog or catalog)[bayId]
    local valid,code=Presentation.validateEntry(entry)
    if not valid then return nil,code end
    if not entry.approved and options.review~=true then return nil,"art_not_approved" end
    local r=copy(entry.registration)
    return {path=entry.path,bayId=bayId,approved=entry.approved,review=options.review==true,
        mirrorX=entry.mirrorX,x=r.x,y=r.y,originX=r.originX,originY=r.originY,
        scale=r.scale,depthY=r.depthY,textureWidth=r.textureWidth,textureHeight=r.textureHeight}
end
function Presentation.draw(plan,getImage,graphics)
    if not plan or type(getImage)~="function" then return false,"plan_required" end
    local okay,image=pcall(getImage,plan.path)
    if not okay or not image or type(image.getDimensions)~="function" then return false,"image_unavailable" end
    local width,height=image:getDimensions()
    if width~=plan.textureWidth or height~=plan.textureHeight then return false,"image_dimensions" end
    graphics=graphics or (love and love.graphics)
    if not graphics then return false,"graphics_unavailable" end
    graphics.setColor(1,1,1,1)
    graphics.draw(image,plan.x,plan.y,0,plan.scale*(plan.mirrorX and -1 or 1),
        plan.scale,plan.originX,plan.originY)
    return true
end
return Presentation
