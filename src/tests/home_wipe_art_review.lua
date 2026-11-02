local Review={}
function Review.run(check,folder)
 local Art=require("src.home_wipe_art");local R=require("src.home_wipe_registration")
 local Layout=require("src.home_layouts");local Catalog=require("src.home_catalog")
 local function save(canvas,name)
  local data=canvas:newImageData();local bytes=data:encode("png");local f=assert(io.open(folder.."/"..name..".png","wb"))
  f:write(bytes:getString());f:close();bytes:release();data:release()
 end
 local function inside(p,x,y)
  local yes=false;local j=#p-1
  for i=1,#p,2 do
   local ax,ay,bx,by=p[i],p[i+1],p[j],p[j+1]
   if (ay>y)~=(by>y) and x<(bx-ax)*(y-ay)/(by-ay)+ax then yes=not yes end;j=i
  end
  return yes
 end
 local all=love.graphics.newCanvas(960,2048)
 love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.clear(.13,.16,.18,1);love.graphics.pop()
 for row,d in ipairs(R.order) do
  local strip=love.graphics.newCanvas(960,256)
  love.graphics.push("all");love.graphics.setCanvas(strip);love.graphics.clear()
  for frame=1,3 do
   love.graphics.push();love.graphics.translate((frame-1)*320+160,210);love.graphics.scale(1.7)
   Art.draw(d,frame,0,0,{});love.graphics.pop()
   check("home_wipe_review_clock_"..d..frame,Art.frame((frame-1)/R.fps+.001)==frame)
  end
  love.graphics.pop();save(strip,"wipe-"..d.."-assembled")
  love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.setColor(1,1,1,1);love.graphics.setShader()
  love.graphics.draw(strip,0,(row-1)*256);love.graphics.print(d,8,(row-1)*256+8);love.graphics.pop();strip:release()
 end
 save(all,"wipe-all-directions");all:release()
 local fixtures=love.graphics.newCanvas(960,1920);local report={"apartment\tfixture\tdirection\tphase\tx\ty\ton_fixture"}
 local shader=love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
 love.graphics.push("all");love.graphics.setCanvas(fixtures);love.graphics.clear(.13,.16,.18,1)
 for apartment,id in ipairs(Catalog.ORDER) do
  local floor=love.graphics.newImage(Catalog.APARTMENTS[id].floorPath)
  for index,name in ipairs({"sink","bath"}) do
   local state=require("src.tests.home_dining_test").fresh(id)
   local fixture=Layout.DATA[id].fixtures[name];local x,y,d=Art.standingPose(state,name)
   assert(x,"No cleaning stance: "..id.." / "..name)
   local row=(apartment-1)*2+index
   for phase=1,3 do
    local c=Art.contact(d,phase);local px,py=Layout.toSource(x+c.x,y+c.y)
    report[#report+1]=string.format("%s\t%s\t%s\t%d\t%.1f\t%.1f\t%s",id,name,d,phase,px,py,tostring(inside(fixture.outline,px,py)))
    check("home_wipe_review_fixture_contact_"..id.."_"..name..phase,Art.onFixture(state,name,d,phase,x,y))
    love.graphics.push();love.graphics.setScissor((phase-1)*320,(row-1)*240,320,240)
    love.graphics.translate((phase-1)*320+160,(row-1)*240+200);love.graphics.scale(1.7);love.graphics.translate(-x,-y)
    love.graphics.setShader(shader);love.graphics.setColor(1,1,1,1);love.graphics.draw(floor,Layout.X,Layout.Y,0,Layout.SCALE,Layout.SCALE)
    Art.draw(d,phase,x,y,{});love.graphics.pop();love.graphics.setScissor();love.graphics.setShader();love.graphics.setColor(1,1,1,1)
    love.graphics.print(id.." / "..name.." / "..phase,(phase-1)*320+8,(row-1)*240+8)
   end
  end
  floor:release()
 end
 love.graphics.pop();save(fixtures,"wipe-fixture-contact");fixtures:release();shader:release()
 local f=assert(io.open(folder.."/wiping-registration.tsv","w"));f:write(table.concat(report,"\n"));f:close()
 check("home_wipe_review_cache_bounded",Art.cachedPhases()==4);Art.release()
 check("home_wipe_review_release",Art.cachedPhases()==0)
end
return Review
