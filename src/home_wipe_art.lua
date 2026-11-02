local R=require("src.home_wipe_registration")
local Colorways=require("src.rabbit_colorways")
local Art={};local phases={};local cloth,clothQuads,bodyShader,propShader
local root="assets/generated/home-wipe-v2/"
function Art.frame(seconds,kind)
 return R.sequence[math.floor(math.max(0,seconds)*(kind=="scrub" and 7 or R.fps))%#R.sequence+1]
end
function Art.contact(direction,frame)
 local v=assert(R.views[direction]);local a=assert(v.frames[frame])
 local scale=a[5] or v.scale
 return {x=(a[3]-a[1])*scale,y=(a[4]-a[2])*scale,ox=v.cloth[1],oy=v.cloth[2],scale=.055}
end
local function inside(p,x,y)
 local yes=false;local j=#p-1
 for i=1,#p,2 do
  local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1]
  if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then yes=not yes end;j=i
 end
 return yes
end
function Art.onFixture(state,name,direction,frame,x,y)
 local Layout=require("src.home_layouts");local fixture=Layout.get(state).fixtures[name]
 local c=Art.contact(direction,frame);local px,py=Layout.toSource(x+c.x,y+c.y)
 return inside(fixture.outline,px,py)
end
function Art.standingPose(state,name)
 local Layout=require("src.home_layouts");local fixture=Layout.get(state).fixtures[name]
 if not fixture then return nil end
 local x,y=Layout.toWorld(unpack(fixture.approach))
 local d=require("src.character_animation").authoredDirection(fixture.x-fixture.approach[1],(fixture.y-fixture.approach[2])*2)
 local offset=R.fixtureOffsets[state.home.apartmentId] and R.fixtureOffsets[state.home.apartmentId][name] or {0,0}
 x,y=x+offset[1],y+offset[2]
 local assets={getData=function()return Layout.mask(state.home.apartmentId) end}
 local obstacles=require("src.home_furniture").obstacles(state);local Navigation=require("src.navigation")
 for _,shift in ipairs({{0,0},{-3,0},{3,0},{0,-3},{0,3},{-6,0},{6,0},{0,-6},{0,6},{-6,-6},{6,-6},{-6,6},{6,6}}) do
  local px,py=x+shift[1],y+shift[2]
  if Navigation.isWalkable(assets,px,py,obstacles) then
   local clear=true
   for frame=1,3 do if not Art.onFixture(state,name,d,frame,px,py) then clear=false;break end end
   if clear then return px,py,d end
  end
 end
end
local function resource(frame,direction)
 local v=R.views[direction];local override=v.override and v.override[frame]
 local key=override or frame
 if phases[key] then return phases[key] end
 local image=love.graphics.newImage(root..(override or "phase-"..frame.."-body.png"));image:setFilter("linear","linear")
 local iw,ih=image:getDimensions();assert(iw==1536 and ih==1024,"Unregistered wiping atlas dimensions")
 local a={image=image,quads={},hands={},offsets={}}
 for _,i in ipairs(override and {v.index} or {1,2,3,4,5,6,7,8}) do
  local d=R.order[i];local x,y=(i-1)%4*384,math.floor((i-1)/4)*512
  if override then x,y=0,0 end
  local region=override and {0,0,iw,ih} or R.regions[frame] and R.regions[frame][i] or {x,y,384,500}
  a.quads[i]=love.graphics.newQuad(region[1],region[2],region[3],region[4],iw,ih)
  a.offsets[i]={region[1]-x,region[2]-y}
  local r=R.views[d].frames[frame];local vertices={}
  local function vertex(px,py)return {px,py,(x+px)/iw,(y+py)/ih,1,1,1,1} end
  -- Only the palm/fingers are restored over the rag; no second arm or prop.
  local factor=override and .18/(r[5] or .18) or 1
  for n=0,15 do
   local t,u=n*math.pi/8,(n+1)*math.pi/8
   vertices[#vertices+1]=vertex(r[3],r[4]-9*factor)
   vertices[#vertices+1]=vertex(r[3]+math.cos(t)*38*factor,r[4]-9*factor+math.sin(t)*25*factor)
   vertices[#vertices+1]=vertex(r[3]+math.cos(u)*38*factor,r[4]-9*factor+math.sin(u)*25*factor)
  end
  a.hands[i]=love.graphics.newMesh(vertices,"triangles","static");a.hands[i]:setTexture(image)
 end
 phases[key]=a;return a
end
function Art.draw(direction,frame,x,y,player)
 local v=R.views[direction];local r=v.frames[frame];local a=resource(frame,direction);local c=Art.contact(direction,frame)
 local scale=r[5] or v.scale
 if not cloth then
  cloth=love.graphics.newImage(root.."cloth-eight-directions.png");cloth:setFilter("linear","linear");clothQuads={}
  for i=1,8 do clothQuads[i]=love.graphics.newQuad((i-1)%4*384,math.floor((i-1)/4)*512,384,512,cloth:getDimensions()) end
 end
 propShader=propShader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
 bodyShader=bodyShader or love.graphics.newShader(Colorways.blendShaderSource()..[[
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return applyRabbitColorways(p)*c;}]])
 love.graphics.push("all");love.graphics.setColor(1,1,1,1)
 local function body()
  love.graphics.setShader(bodyShader);Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
  local offset=a.offsets[v.index]
  love.graphics.draw(a.image,a.quads[v.index],x,y,0,scale,scale,r[1]-offset[1],r[2]-offset[2])
 end
 if not v.rear then body() end
 love.graphics.setShader(propShader);love.graphics.draw(cloth,clothQuads[v.index],x+c.x,y+c.y,0,c.scale,c.scale,c.ox,c.oy)
 if v.rear then body() else love.graphics.setShader(bodyShader);love.graphics.draw(a.hands[v.index],x,y,0,scale,scale,r[1],r[2]) end
 love.graphics.pop();return c
end
function Art.cachedPhases()local n=0;for _ in pairs(phases) do n=n+1 end;return n end
function Art.release()
 for _,a in pairs(phases) do a.image:release();for _,q in pairs(a.quads) do q:release() end;for _,m in pairs(a.hands) do m:release() end end
 phases={}
 if cloth then cloth:release();cloth=nil;for _,q in ipairs(clothQuads) do q:release() end;clothQuads=nil end
 if bodyShader then bodyShader:release();bodyShader=nil end
 if propShader then propShader:release();propShader=nil end
end
return Art
