local Loader=require('src.image_loader')
local Art={}

local ATLAS='assets/generated/grocery-ui-v1/grocery-products-atlas.png'
local EMBLEM='assets/generated/grocery-ui-v1/grocery-ui-emblem.png'
local productIndex={
    vegetables=0,bread=1,cereal=2,sandwich=3,
    drink=4,meal=5,cup=6,meal_pack=7,
}
local images={}
local quads={}

local function image(key,path)
    if images[key] then return images[key] end
    local loaded=Loader.load(path)
    if not loaded then return nil end
    loaded:setFilter('linear','linear')
    images[key]=loaded
    return loaded
end

function Art.drawProduct(id,x,y,size)
    local index=productIndex[id]
    if index==nil then return false end
    local atlas=image('products',ATLAS)
    if not atlas then return false end
    local quad=quads[index]
    if not quad then
        local width,height=atlas:getDimensions()
        quad=love.graphics.newQuad((index%4)*128,math.floor(index/4)*128,128,128,width,height)
        quads[index]=quad
    end
    local g=love.graphics
    g.push('all');g.setColor(1,1,1,1)
    g.draw(atlas,quad,x,y,0,size/128,size/128,64,64)
    g.pop()
    return true
end

function Art.drawEmblem(x,y,size)
    local badge=image('emblem',EMBLEM)
    if not badge then return false end
    local g=love.graphics
    g.push('all');g.setColor(1,1,1,1)
    g.draw(badge,x,y,0,size/128,size/128,64,64)
    g.pop()
    return true
end

return Art
