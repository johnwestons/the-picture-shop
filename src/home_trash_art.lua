local R=require("src.home_trash_registration")
local Colorways=require("src.rabbit_colorways")
local Art={};local phases={};local bag,bagQuads,bodyShader,propShader
local root="assets/generated/home-trash-v2/"
function Art.frame(seconds,duration)
 local step=math.min(.3,math.max(.01,(duration or 4)*.2));seconds=math.max(0,seconds)
 if seconds<step then return 1 elseif seconds<step*2 then return 2 end
 return 3+math.floor((seconds-step*2)/.45)%2
end
function Art.contact(direction,frame)
 local v=assert(R.views[direction]);local a=assert(v.frames[frame]);local k=v.knot
 local x,y=(a[3]-a[1])*a[5],(a[4]-a[2])*a[5]
 local bottom=y+(k[3]-k[2])*.075
 return {x=x,y=y,ox=k[1],oy=k[2],scale=.075,bottom=bottom,
  valid=a[3]>0 and a[3]<384 and a[4]>0 and a[4]<512 and bottom<=3}
end
local function resource(frame)
 if phases[frame] then return phases[frame] end
 local image=love.graphics.newImage(root.."phase-"..frame.."-body.png");image:setFilter("linear","linear")
 local a={image=image,quads={},hands={}};local iw,ih=image:getDimensions()
 for i,d in ipairs(R.order) do
  local x,y=(i-1)%4*384,math.floor((i-1)/4)*512
  -- Atlas gutters exclude a few pixels of a neighbouring ear/tail at cell edges.
  a.quads[i]=love.graphics.newQuad(x+8,y,368,500,iw,ih)
  local r=R.views[d].frames[frame];local vertices={}
  local function vertex(px,py)return {px,py,(x+px)/iw,(y+py)/ih,1,1,1,1} end
  -- Redraw just the curled fingers over the separate knot in front-facing views.
  for n=0,15 do
   local t,u=n*math.pi/8,(n+1)*math.pi/8
   vertices[#vertices+1]=vertex(r[3],r[4])
   vertices[#vertices+1]=vertex(r[3]+math.cos(t)*28,r[4]+math.sin(t)*21)
   vertices[#vertices+1]=vertex(r[3]+math.cos(u)*28,r[4]+math.sin(u)*21)
  end
  a.hands[i]=love.graphics.newMesh(vertices,"triangles","static");a.hands[i]:setTexture(image)
 end
 phases[frame]=a;return a
end
function Art.draw(direction,frame,x,y,player)
 local v=R.views[direction];local r=v.frames[frame];local a=resource(frame);local c=Art.contact(direction,frame)
 if not bag then
  bag=love.graphics.newImage(root.."bag-eight-directions.png");bag:setFilter("linear","linear");bagQuads={}
  for i=1,8 do bagQuads[i]=love.graphics.newQuad((i-1)%4*384,math.floor((i-1)/4)*512,384,512,bag:getDimensions()) end
 end
 propShader=propShader or love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
 bodyShader=bodyShader or love.graphics.newShader(Colorways.blendShaderSource()..[[
 vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return applyRabbitColorways(p)*c;}]])
 love.graphics.push("all");love.graphics.setColor(1,1,1,1)
 local function body()
  love.graphics.setShader(bodyShader);Colorways.configureShader(bodyShader,player and player.furColorway,player and player.overallsColorway)
  love.graphics.draw(a.image,a.quads[v.index],x,y,0,r[5],r[5],r[1]-8,r[2])
 end
 if not v.rear then body() end
 love.graphics.setShader(propShader);love.graphics.draw(bag,bagQuads[v.index],x+c.x,y+c.y,0,c.scale,c.scale,c.ox,c.oy)
 if v.rear then body() else love.graphics.setShader(bodyShader);love.graphics.draw(a.hands[v.index],x,y,0,r[5],r[5],r[1],r[2]) end
 love.graphics.pop();return c
end
function Art.cachedPhases()local n=0;for _ in pairs(phases) do n=n+1 end;return n end
function Art.release()
 for _,a in pairs(phases) do a.image:release();for _,q in ipairs(a.quads) do q:release() end;for _,m in ipairs(a.hands) do m:release() end end
 phases={}
 if bag then bag:release();bag=nil;for _,q in ipairs(bagQuads) do q:release() end;bagQuads=nil end
 if bodyShader then bodyShader:release();bodyShader=nil end
 if propShader then propShader:release();propShader=nil end
end
return Art
