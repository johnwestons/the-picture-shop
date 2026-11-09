local Images=require("src.home_art_resources")
local Preload=require("src.home_art_preload")
local Props={};local image,shader,frames
local columns={{0,400},{400,368},{768,384},{1152,384}}
local function load()
    if image then return true end
    image=Images.load("props","assets/generated/home-routines-v1/household-props.png");if not image then return false end;image:setFilter("linear","linear");frames={}
    for i=1,8 do
        local c=columns[(i-1)%4+1]
        frames[i]=love.graphics.newQuad(c[1],math.floor((i-1)/4)*512,c[2],512,image:getDimensions())
    end
    shader=love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
end
function Props.prewarm() load();return image~=nil end
function Props.draw(index,x,y,scale,mirror,rotation,ox,oy)
    if not Preload.want("props",Props.prewarm) then return false end
    load();love.graphics.push("all");love.graphics.setShader(shader);love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,frames[index],x,y,rotation or 0,scale*(mirror or 1),scale,ox or 192,oy or 300)
    love.graphics.pop()
end
function Props.release()
    Images.release("props")
    if image then image:release();for _,quad in ipairs(frames) do quad:release() end;shader:release() end
    image,shader,frames=nil,nil,nil
end
return Props
