-- Pure contextual presentation: only home_chores changes clothes/cycle state.
local R=require("src.home_laundry_registration")
local Colorways=require("src.rabbit_colorways")
local Art={};local phases={};local props;local bodyShader,propShader
local root="assets/generated/home-laundry-v2/"
local function clamp(n)return math.max(0,math.min(1,n)) end
function Art.progress(seconds,duration)return clamp(math.max(0,seconds or 0)/math.max(.0001,duration or 4)) end
function Art.frame(seconds,duration,kind)
 local t=Art.progress(seconds,duration)
 if kind=="unload" then
  if t<.12 then return 4 elseif t<.38 then return 3 elseif t<.60 then return 2 elseif t<.84 then return 1 end
  return 4
 end
 if t<.20 then return 1 elseif t<.42 then return 2 elseif t<.72 then return 3 end
 return 4
end
function Art.bundleMode(kind,frame,progress)
 if kind=="unload" and frame==4 then return (progress or 0)>=.84 and "basket" or nil end
 if frame==4 then return nil end
 return "hand"
end
function Art.contact(direction,frame)
 local v=assert(R.views[direction]);local f=assert(v.frames[frame]);local a,b=f.hands[1],f.hands[2]
 local first=v.frames[1];local x,y=((a[1]+b[1])/2-f.foot[1])*v.scale,((a[2]+b[2])/2-f.foot[2])*v.scale
 local bx=((first.hands[1][1]+first.hands[2][1])/2-first.foot[1])*v.scale
 local by=((first.hands[1][2]+first.hands[2][2])/2-first.foot[2])*v.scale+10
 return {x=x,y=y,basketX=bx,basketY=by,bundleScale=R.bundle.scale,
  valid=f.foot[1]>0 and f.foot[1]<f.crop[3] and f.foot[2]>0 and f.foot[2]<f.crop[4]
   and x>-50 and x<50 and y<0 and by<8 and by>-12}
end
function Art.washerDoor(state)
 local w=assert(R.washers[state.home.apartmentId]);return require("src.home_layouts").toWorld(unpack(w.door))
end
function Art.standingPose(state,direction)
 local Layout=require("src.home_layouts");local Navigation=require("src.navigation")
 local w=R.washers[state.home.apartmentId];if not w then return nil end
 direction=direction or w.direction
 local doorX,doorY=Art.washerDoor(state);local c=Art.contact(direction,3)
 local x,y=doorX-c.x,doorY-c.y
 local assets={getData=function()return Layout.mask(state.home.apartmentId) end}
 local obstacles=require("src.home_furniture").obstacles(state)
 local offsets={{0,0},{0,3},{3,0},{-3,0},{0,-3},{3,3},{-3,3},{0,6},{6,0},{-6,0},{3,6},{6,3},{-3,6},{-6,3},{0,9},{9,0},{-9,0}}
 for _,o in ipairs(offsets) do
  if Navigation.isWalkable(assets,x+o[1],y+o[2],obstacles) then
   return x+o[1],y+o[2],direction,doorX,doorY,math.sqrt(o[1]^2+o[2]^2)
  end
 end
end
local function resource(phase)
 if phases[phase] then return phases[phase] end
 local im=love.graphics.newImage(root.."phase-"..phase.."-body.png");im:setFilter("linear","linear")
 local iw,ih=im:getDimensions();assert(iw==1536 and ih==1024,"Unregistered laundry source size")
 local a={image=im,quads={},hands={}}
 for i,d in ipairs(R.order) do
  local f=R.views[d].frames[phase];local crop=f.crop
  a.quads[i]=love.graphics.newQuad(crop[1],crop[2],crop[3],crop[4],iw,ih)
  local vertices={}
  local function vertex(px,py)return {px,py,(crop[1]+px)/iw,(crop[2]+py)/ih,1,1,1,1} end
  for _,h in ipairs(f.hands) do
   for n=0,15 do
    local t,u=n*math.pi/8,(n+1)*math.pi/8
    vertices[#vertices+1]=vertex(h[1],h[2]);vertices[#vertices+1]=vertex(h[1]+math.cos(t)*20,h[2]+math.sin(t)*17)
    vertices[#vertices+1]=vertex(h[1]+math.cos(u)*20,h[2]+math.sin(u)*17)
   end
  end
  a.hands[i]=love.graphics.newMesh(vertices,"triangles","static");a.hands[i]:setTexture(im)
 end
 phases[phase]=a;return a
end
local function propResources()
 if props then return props end
 props={}
 for _,name in ipairs({"basket","bundle"}) do
  local im=love.graphics.newImage(root..name.."-eight-directions.png");im:setFilter("linear","linear")
  local iw,ih=im:getDimensions();assert(iw==1536 and ih==1024,"Unregistered laundry prop size")
  local p={image=im,quads={}}
  for i=1,8 do local r=R[name].rects[i];p.quads[i]=love.graphics.newQuad(r[1],r[2],r[3],r[4],iw,ih) end
  props[name]=p
 end
 return props
end
local function shaders()
 propShader=propShader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
 bodyShader=bodyShader or love.graphics.newShader(Colorways.blendShaderSource()..[[
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return applyRabbitColorways(p)*c;}]])
end
function Art.draw(direction,frame,x,y,player,kind,progress)
 local v=assert(R.views[direction]);local f=assert(v.frames[frame]);local a=resource(frame);local p=propResources()
 local c=Art.contact(direction,frame);local mode=Art.bundleMode(kind or "loadwash",frame,progress);shaders()
 love.graphics.push("all");love.graphics.setColor(1,1,1,1)
 local function body()
  love.graphics.setShader(bodyShader);Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
  love.graphics.draw(a.image,a.quads[v.index],x,y,0,v.scale,v.scale,f.foot[1],f.foot[2])
 end
 local function tools()
  love.graphics.setShader(propShader)
  local b=R.basket.base[v.index]
  love.graphics.draw(p.basket.image,p.basket.quads[v.index],x+c.basketX,y+c.basketY,0,R.basket.scale,R.basket.scale,b[1],b[2])
  if mode then
   local o=R.bundle.centre[v.index];local hx,hy=c.x,c.y
   if mode=="basket" then hx,hy=c.basketX,c.basketY-10 end
   love.graphics.draw(p.bundle.image,p.bundle.quads[v.index],x+hx,y+hy,0,R.bundle.scale,R.bundle.scale,o[1],o[2])
  end
 end
 if not v.rear then body() end
 tools()
 if v.rear then body() elseif mode=="hand" then
  love.graphics.setShader(bodyShader);love.graphics.draw(a.hands[v.index],x,y,0,v.scale,v.scale,f.foot[1],f.foot[2])
 end
 love.graphics.pop();c.bundleMode=mode;return c
end
function Art.cachedPhases()local n=0;for _ in pairs(phases) do n=n+1 end;return n end
function Art.release()
 for _,a in pairs(phases) do
  a.image:release();for _,q in ipairs(a.quads) do q:release() end;for _,m in ipairs(a.hands) do m:release() end
 end
 phases={}
 if props then for _,p in pairs(props) do p.image:release();for _,q in ipairs(p.quads) do q:release() end end;props=nil end
 if bodyShader then bodyShader:release();bodyShader=nil end
 if propShader then propShader:release();propShader=nil end
end
return Art
