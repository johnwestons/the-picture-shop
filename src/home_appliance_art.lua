-- Large, interactive appliance presentation used by the apartment GUI.
-- The refrigerator cabinet and door are separate generated layers so its door
-- can swing open without fading between two complete fridge images.
local Food=require("src.home_food_catalog")
local FoodArt=require("src.home_food_art")
local Art={}
local fridgeAssets={}
local stoveImage,stoveFront
local badgeFont

local function loadFridge(kind)
    kind=kind=="mini_fridge" and "mini_fridge" or "refrigerator"
    if fridgeAssets[kind] then return fridgeAssets[kind] end
    local path="assets/generated/home-appliance-gui-v1/"..(kind=="mini_fridge" and "mini-fridge" or "refrigerator").."-layers.png"
    local ok,image=pcall(love.graphics.newImage,path)
    if not ok then return false end
    image:setFilter("linear","linear")
    local w,h=image:getDimensions();local cell=w/2
    local asset={image=image}
    asset.interior=love.graphics.newQuad(0,0,cell,h,w,h)
    asset.door=love.graphics.newQuad(cell,0,cell,h,w,h)
    if kind=="mini_fridge" then
        asset.slots={{265,290},{430,290},{595,290},{265,465},{430,465},{595,465},{430,648}}
        -- The door layer has a transparent left margin; use the visible hinge
        -- edge, not the cell's earlier estimate, as the swing pivot.
        asset.hingeX,asset.hingeY=226,460
    else
        asset.slots={{310,226},{402,226},{494,226},{586,226},
            {310,354},{402,354},{494,354},{586,354},
            {310,482},{402,482},{494,482},{586,482},{448,675}}
        asset.hingeX,asset.hingeY=242,443
    end
    fridgeAssets[kind]=asset
    return asset
end

local function loadStove()
    if stoveImage then return true end
    local ok,image=pcall(love.graphics.newImage,"assets/generated/home-furniture-v1/stove-eight-directions.png")
    if not ok then return false end
    stoveImage=image;stoveImage:setFilter("linear","linear")
    local w,h=stoveImage:getDimensions()
    stoveFront=love.graphics.newQuad(384,0,384,512,w,h)
    return true
end

local function clamp01(value)
    return math.max(0,math.min(1,tonumber(value) or 0))
end

function Art.drawFridge(x,y,scale,opening,contents,kind)
    local asset=loadFridge(kind)
    if not asset then return false end
    scale=scale or .43
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(asset.image,asset.interior,x,y,0,scale,scale)
    local stored={}
    for _,kind in ipairs(require("src.home_objects").FOODS) do
        local count=contents and tonumber(contents[kind]) or 0
        if count and count>0 then stored[#stored+1]={kind=kind,count=count} end
    end
    if #stored==0 then
        love.graphics.setColor(.79,.86,.88,.8)
        love.graphics.printf("EMPTY",x+319*scale,y+422*scale,245*scale,"center")
    else
        for i,entry in ipairs(stored) do
            local slot=asset.slots[i]
            if not slot then break end
            local food=Food.ITEMS[entry.kind]
            local ix,iy=x+slot[1]*scale,y+slot[2]*scale
            if food then FoodArt.draw(food.sprite,ix,iy,29) end
            if entry.count>1 then
                badgeFont=badgeFont or love.graphics.newFont(12)
                love.graphics.setFont(badgeFont)
                love.graphics.setColor(.025,.045,.055,.92)
                love.graphics.rectangle("fill",ix+8,iy+5,23,16,4)
                love.graphics.setColor(1,.96,.78,1)
                love.graphics.printf(tostring(entry.count),ix+8,iy+6,23,"center")
            end
        end
        if #stored>#asset.slots then
            badgeFont=badgeFont or love.graphics.newFont(12)
            love.graphics.setFont(badgeFont)
            love.graphics.setColor(.88,.92,.92,.9)
            love.graphics.printf("+"..(#stored-#asset.slots),x+393*scale,y+692*scale,110*scale,"center")
        end
    end

    local progress=clamp01(opening)
    local eased=progress*progress*(3-2*progress)
    local hingeX,hingeY=asset.hingeX,asset.hingeY
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(asset.image,asset.door,
        x+hingeX*scale,y+hingeY*scale,-.92*eased,
        scale*(1-.82*eased),scale,hingeX,hingeY)
    love.graphics.pop()
    return true
end

local function drawSteam(x,y,phase)
    love.graphics.setLineWidth(2)
    for i=1,3 do
        local t=phase+i*.72
        local sx=x+(i-2)*10
        local points={}
        for step=0,5 do
            local p=step/5
            points[#points+1]=sx+math.sin(t+p*4.2)*4
            points[#points+1]=y-p*31
        end
        love.graphics.setColor(.87,.93,.93,.34+math.sin(t)*.10)
        love.graphics.line(points)
    end
end

function Art.drawStove(x,y,scale,cooking,seconds)
    if not loadStove() then return false end
    scale=scale or .78
    love.graphics.push("all")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(stoveImage,stoveFront,x,y,0,scale,scale)
    local panX,panY=x+147*scale,y+166*scale
    if cooking then
        local pulse=.72+.28*math.sin((seconds or 0)*5)
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1,.24,.035,.28*pulse)
        love.graphics.ellipse("fill",panX,panY,27*scale,13*scale)
        love.graphics.setBlendMode("alpha")
    end
    local okay,pan=pcall(function()
        return require("src.home_cooking_art").drawPan("south",panX,panY)
    end)
    if not okay or pan==false then
        love.graphics.setColor(.17,.13,.11,1)
        love.graphics.ellipse("fill",panX,panY,19*scale,8*scale)
        love.graphics.setColor(.54,.53,.50,1)
        love.graphics.ellipse("line",panX,panY,19*scale,8*scale)
    end
    if cooking then drawSteam(panX,panY-10,seconds or 0) end
    love.graphics.pop()
    return true
end

function Art.release()
    for _,asset in pairs(fridgeAssets) do
        asset.interior:release();asset.door:release();asset.image:release()
    end
    fridgeAssets={}
    if stoveFront then stoveFront:release();stoveFront=nil end
    if stoveImage then stoveImage:release();stoveImage=nil end
end

return Art
