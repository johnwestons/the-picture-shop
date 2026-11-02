-- Character and prop share a directional frame and registered grip contacts.
local Registration=require("src.home_sweep_registration")
local Colorways=require("src.rabbit_colorways")
local Art={};local cache={};local broom,propShader,bodyShader,propQuads;local use=0
local root="assets/generated/home-routines-v2/"
function Art.frame(seconds)return Registration.sequence[math.floor(math.max(0,seconds)*Registration.fps)%#Registration.sequence+1] end
local function dispose(a)
    a.image:release();for _,q in ipairs(a.frames) do q:release() end
    for _,hands in ipairs(a.handMeshes) do for _,mesh in ipairs(hands) do mesh:release() end end
end
function Art.contact(direction,frame)
    local v=assert(Registration.views[direction]);local r=assert(v.grips[frame]);local b=Registration.brooms[v.index]
    local hx,hy=(r[3]-r[1])*v.scale,(r[4]-r[2])*v.scale
    local rotation=math.atan2(r[6]-r[4],r[5]-r[3])-math.atan2(b[4]-b[2],b[3]-b[1])
    local c,s=math.cos(rotation),math.sin(rotation);local scale=.17
    local function ry(dx,dy)return dx*s+dy*c end
    local ground=v.ground or ((direction=="north" or direction=="northeast" or direction=="northwest") and -10 or 0)
    local dx,dy=b[3]-b[1],b[4]-b[2]
    local t=(ry(b[5]-b[1],b[6]-b[2])+(hy-ground)/scale)/ry(dx,dy)
    local lower=t+math.sqrt((r[5]-r[3])^2+(r[6]-r[4])^2)*v.scale/scale/math.sqrt(dx*dx+dy*dy)
    return {x=hx,y=hy,rotation=rotation,scale=scale,ox=b[1]+dx*t,oy=b[2]+dy*t,
        upper=t,lower=lower,ground=ground,valid=t>=0 and lower<=1.06}
end
local function resource(direction)
    use=use+1
    if cache[direction] then cache[direction].used=use;return cache[direction] end
    local count,oldest,oldestUse=0,nil,math.huge
    for d,a in pairs(cache) do count=count+1;if a.used<oldestUse then oldest,oldestUse=d,a.used end end
    if count>=4 then dispose(cache[oldest]);cache[oldest]=nil end
    local v=Registration.views[direction];local image=love.graphics.newImage(root..v.file);image:setFilter("linear","linear")
    local frames,handMeshes={},{}
    for i=1,4 do
        local region=v.regions and v.regions[i] or {(i-1)%v.cols*v.w,math.floor((i-1)/v.cols)*v.h,v.w,v.h}
        frames[i]=love.graphics.newQuad(region[1],region[2],region[3],region[4],image:getDimensions())
        handMeshes[i]={}
        for grip=1,2 do
            local r=v.grips[i];local hx,hy=r[grip*2+1],r[grip*2+2];local radius=v.w==384 and 20 or 33
            local vertices={};local iw,ih=image:getDimensions()
            local function vertex(x,y)return {x,y,(region[1]+x)/iw,(region[2]+y)/ih,1,1,1,1} end
            for n=0,11 do
                local a,b=n*math.pi/6,(n+1)*math.pi/6
                vertices[#vertices+1]=vertex(hx,hy)
                vertices[#vertices+1]=vertex(hx+math.cos(a)*radius,hy+math.sin(a)*radius)
                vertices[#vertices+1]=vertex(hx+math.cos(b)*radius,hy+math.sin(b)*radius)
            end
            local mesh=love.graphics.newMesh(vertices,"triangles","static");mesh:setTexture(image);handMeshes[i][grip]=mesh
        end
    end
    local asset={image=image,frames=frames,handMeshes=handMeshes,used=use};cache[direction]=asset;return asset
end
function Art.draw(direction,frame,x,y,player)
    local v=Registration.views[direction];local r=v.grips[frame];local contact=Art.contact(direction,frame)
    local asset=resource(direction)
    if not broom then
        broom=love.graphics.newImage(root.."broom-eight-directions-long-shaft.png");propQuads={}
        for i=1,8 do propQuads[i]=love.graphics.newQuad((i-1)%4*384,math.floor((i-1)/4)*512,384,512,broom:getDimensions()) end
    end
    propShader=propShader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
    bodyShader=bodyShader or love.graphics.newShader(Colorways.blendShaderSource()..[[
vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return applyRabbitColorways(p)*c;}]])
    love.graphics.push("all");love.graphics.setColor(1,1,1,1)
    local rear=direction=="north" or direction=="northeast" or direction=="northwest"
    local function drawBody()
        love.graphics.setShader(bodyShader);Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
        love.graphics.draw(asset.image,asset.frames[frame],x,y,0,v.scale,v.scale,r[1],r[2])
    end
    if not rear then drawBody() end
    love.graphics.setShader(propShader)
    love.graphics.draw(broom,propQuads[v.index],x+contact.x,y+contact.y,contact.rotation,contact.scale,contact.scale,contact.ox,contact.oy)
    if rear then drawBody() else
        love.graphics.setShader(bodyShader)
        for _,mesh in ipairs(asset.handMeshes[frame]) do love.graphics.draw(mesh,x,y,0,v.scale,v.scale,r[1],r[2]) end
    end
    love.graphics.pop()
    return contact
end
function Art.release()
    for _,a in pairs(cache) do dispose(a) end
    cache={};if broom then broom:release();broom=nil;for _,q in ipairs(propQuads) do q:release() end;propQuads=nil end
    if propShader then propShader:release();propShader=nil end
    if bodyShader then bodyShader:release();bodyShader=nil end
end
function Art.cachedDirections()local n=0;for _ in pairs(cache) do n=n+1 end;return n end
return Art
