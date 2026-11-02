-- Body, hand and directional spoon share contacts; the stove owns the pan.
local R=require("src.home_cooking_registration")
local Colorways=require("src.rabbit_colorways")
local Art={};local cache={};local props;local bodyShader,propShader;local use=0
local root="assets/generated/home-cooking-v2/"
function Art.frame(seconds)return R.sequence[math.floor(math.max(0,seconds)*R.fps)%#R.sequence+1] end
function Art.contact(direction,frame,bowlX,bowlY)
 local v=assert(R.views[direction]);local r=assert(v.grips[frame]);local spoon=R.spoons[v.index]
 local hx,hy=(r[3]-r[1])*v.scale,(r[4]-r[2])*v.scale
 local phase=(frame-1)*math.pi/2
 local tx,ty=(bowlX or v.bowlX)+math.cos(phase)*1.5,(bowlY or v.bowlY)+math.sin(phase)*.7
 local dx,dy=tx-hx,ty-hy;local sx,sy=spoon[7]-spoon[5],spoon[8]-spoon[6]
 local scale=math.sqrt(dx*dx+dy*dy)/math.sqrt(sx*sx+sy*sy)
 return {x=hx,y=hy,tipX=tx,tipY=ty,rotation=math.atan2(dy,dx)-math.atan2(sy,sx),
  scale=scale,ox=spoon[5],oy=spoon[6],valid=scale>.004 and scale<.10 and ty>hy-1}
end
local function dispose(a)
 a.image:release();for _,q in ipairs(a.frames) do q:release() end
 for _,mesh in ipairs(a.hands) do mesh:release() end
end
local function resource(direction)
 use=use+1;if cache[direction] then cache[direction].used=use;return cache[direction] end
 local count,oldest,age=0,nil,math.huge
 for d,a in pairs(cache) do count=count+1;if a.used<age then oldest,age=d,a.used end end
 if count>=4 then dispose(cache[oldest]);cache[oldest]=nil end
 local v=R.views[direction];local image=love.graphics.newImage(root..v.file);image:setFilter("linear","linear")
 local iw,ih=image:getDimensions();assert(iw==1254 and ih==1254,"Unregistered cooking source dimensions")
 local a={image=image,frames={},hands={},used=use}
 for f=1,4 do
  local x,y=(f-1)%2*627,math.floor((f-1)/2)*627
  a.frames[f]=love.graphics.newQuad(x,y,627,627,iw,ih)
  local r=v.grips[f];local vertices={}
  local function vertex(px,py)return {px,py,(x+px)/iw,(y+py)/ih,1,1,1,1} end
  for n=0,11 do
   local first,last=n*math.pi/6,(n+1)*math.pi/6
   vertices[#vertices+1]=vertex(r[3],r[4]);vertices[#vertices+1]=vertex(r[3]+math.cos(first)*27,r[4]+math.sin(first)*27)
   vertices[#vertices+1]=vertex(r[3]+math.cos(last)*27,r[4]+math.sin(last)*27)
  end
  a.hands[f]=love.graphics.newMesh(vertices,"triangles","static");a.hands[f]:setTexture(image)
 end
 cache[direction]=a;return a
end
local function propResources()
 if props then return props end
 props={}
 for _,entry in ipairs({{"pan","saucepan-eight-directions.png",R.pans},{"spoon","spoon-eight-directions.png",R.spoons}}) do
  local image=love.graphics.newImage(root..entry[2]);image:setFilter("linear","linear");local frames={}
  for i,r in ipairs(entry[3]) do frames[i]=love.graphics.newQuad(r[1],r[2],r[3],r[4],image:getDimensions()) end
  props[entry[1]]={image=image,frames=frames}
 end
 return props
end
local function shaders()
 propShader=propShader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
 bodyShader=bodyShader or love.graphics.newShader(Colorways.blendShaderSource()..[[
vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return applyRabbitColorways(p)*c;}]])
end
function Art.stoveTop(item)
 local entry=require("src.home_furniture_catalog").ITEMS.stove;local f=entry.frames[item.direction];local pivot=entry.pivots[f]
 local top=({{205,160},{192,147},{192,160},{220,140},{210,97},{192,88},{190,97},{212,127}})[f]
 return item.x+(top[1]-pivot[1])*entry.scale,item.y+(top[2]-pivot[2])*entry.scale
end
function Art.anchor(direction,item)
 local v=R.views[direction];local pan=R.pans[R.views[item.direction].index];local x,y=Art.stoveTop(item)
 return x+(pan[7]-pan[5])*.075-v.bowlX,y+(pan[8]-pan[6])*.075-v.bowlY
end
function Art.standingPose(state,direction,item)
 local x,y=Art.anchor(direction,item);local Layout=require("src.home_layouts")
 local assets={getData=function()return Layout.mask(state.home.apartmentId) end}
 local obstacles=require("src.home_furniture").obstacles(state);local Navigation=require("src.navigation")
 local offsets={{0,0},{0,3},{3,0},{-3,0},{0,-3},{3,3},{-3,3},{0,6},{6,0},{-6,0},{0,-6}}
 for _,offset in ipairs(offsets) do
  local px,py=x+offset[1],y+offset[2]
  if Navigation.isWalkable(assets,px,py,obstacles) then
   local pan=R.pans[R.views[item.direction].index];local bx,by=Art.stoveTop(item)
   return px,py,bx+(pan[7]-pan[5])*.075-px,by+(pan[8]-pan[6])*.075-py
  end
 end
end
function Art.drawPan(direction,x,y)
 local p=propResources().pan;local i=R.views[direction].index;local r=R.pans[i];shaders()
 love.graphics.push("all");love.graphics.setShader(propShader);love.graphics.setColor(1,1,1,1)
 love.graphics.draw(p.image,p.frames[i],x,y,0,.075,.075,r[5],r[6]);love.graphics.pop()
end
function Art.draw(direction,frame,x,y,player,skipPan,bowlX,bowlY)
 local v=R.views[direction];local r=v.grips[frame];local a=resource(direction);local p=propResources();local c=Art.contact(direction,frame,bowlX,bowlY)
 shaders()
 love.graphics.push("all");love.graphics.setColor(1,1,1,1)
 local rear=direction=="north" or direction=="northwest" or direction=="northeast"
 local function body()
  love.graphics.setShader(bodyShader);Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
  love.graphics.draw(a.image,a.frames[frame],x,y,0,v.scale,v.scale,r[1],r[2])
 end
 if not rear then body() end
 love.graphics.setShader(propShader)
 local pan=R.pans[v.index]
 if not skipPan then love.graphics.draw(p.pan.image,p.pan.frames[v.index],x+v.bowlX,y+v.bowlY,0,.075,.075,pan[7],pan[8]) end
 love.graphics.draw(p.spoon.image,p.spoon.frames[v.index],x+c.x,y+c.y,c.rotation,c.scale,c.scale,c.ox,c.oy)
 if rear then body() else
  love.graphics.setShader(bodyShader);love.graphics.draw(a.hands[frame],x,y,0,v.scale,v.scale,r[1],r[2])
 end
 love.graphics.pop();return c
end
function Art.cachedDirections()local n=0;for _ in pairs(cache) do n=n+1 end;return n end
function Art.release()
 for _,a in pairs(cache) do dispose(a) end;cache={}
 if props then for _,p in pairs(props) do p.image:release();for _,q in ipairs(p.frames) do q:release() end end;props=nil end
 if bodyShader then bodyShader:release();bodyShader=nil end
 if propShader then propShader:release();propShader=nil end
end
return Art
