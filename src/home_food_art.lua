local Art={PATH="assets/generated/home-food-v1/food-and-drink-atlas.png"}
local texture,quads,shader
local function load()
    if texture then return end
    texture=love.graphics.newImage(Art.PATH);texture:setFilter("linear","linear")
    local w,h=texture:getDimensions();quads={}
    for i=1,16 do
        local x,y=((i-1)%4)*w/4,math.floor((i-1)/4)*h/4
        local height=h/4
        -- The generated open-box tip extends slightly below the nominal cell.
        if i==4 then height=326 elseif i==8 then y=326;height=h/2-y end
        quads[i]={quad=love.graphics.newQuad(x,y,w/4,height,w,h),width=w/4,height=height}
    end
    shader=love.graphics.newShader([[vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 p=Texel(tex,uv); if(p.a<0.18) return vec4(0.0); return p*color;
    }]])
end
function Art.draw(index,x,y,size,rotation)
    load();local frame=quads[index or 1];if not frame then return end
    love.graphics.push("all");love.graphics.setShader(shader);love.graphics.setColor(1,1,1,1)
    local scale=size/math.max(frame.width,frame.height)
    love.graphics.draw(texture,frame.quad,x,y,rotation or 0,scale,scale,frame.width/2,frame.height/2)
    love.graphics.pop()
end
function Art.release()
    if texture then texture:release() end
    if quads then for _,f in pairs(quads) do f.quad:release() end end
    if shader then shader:release() end
    texture,quads,shader=nil,nil,nil
end
return Art
