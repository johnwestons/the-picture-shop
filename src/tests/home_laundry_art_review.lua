local Review={}
function Review.run(check,folder)
 local Art=require("src.home_laundry_art");local R=require("src.home_laundry_registration")
 local Layout=require("src.home_layouts");local Fixtures=require("src.tests.home_dining_test")
 local function save(canvas,name)
  local data=canvas:newImageData();local bytes=data:encode("png");local f=assert(io.open(folder.."/"..name..".png","wb"))
  f:write(bytes:getString());f:close();bytes:release();data:release()
 end
 local all=love.graphics.newCanvas(1280,2048);local report={"direction\tphase\thand_x\thand_y\tbasket_x\tbasket_y\tvalid"}
 love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.clear(.13,.16,.18,1);love.graphics.pop()
 for row,d in ipairs(R.order) do
  local strip=love.graphics.newCanvas(1280,256)
  love.graphics.push("all");love.graphics.setCanvas(strip);love.graphics.clear()
  for phase=1,4 do
   love.graphics.push();love.graphics.translate((phase-1)*320+160,210);love.graphics.scale(1.7)
   local c=Art.draw(d,phase,0,0,{},"loadwash",({.1,.3,.6,.9})[phase]);love.graphics.pop()
   check("home_laundry_render_"..d..phase,c.valid and Art.cachedPhases()<=4)
   report[#report+1]=string.format("%s\t%d\t%.2f\t%.2f\t%.2f\t%.2f\t%s",d,phase,c.x,c.y,c.basketX,c.basketY,tostring(c.valid))
  end
  love.graphics.pop();save(strip,"laundry-"..d.."-assembled")
  love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.setShader();love.graphics.setColor(1,1,1,1)
  love.graphics.draw(strip,0,(row-1)*256);love.graphics.print(d,8,(row-1)*256+8);love.graphics.pop();strip:release()
 end
 save(all,"laundry-all-directions");all:release()
 local apartments=love.graphics.newCanvas(1280,1024)
 love.graphics.push("all");love.graphics.setCanvas(apartments);love.graphics.clear(.13,.16,.18,1)
 for i,id in ipairs(require("src.home_catalog").ORDER) do
  love.graphics.setScissor((i-1)%2*640,math.floor((i-1)/2)*512,640,512)
  local s,p=Fixtures.fresh(id);local x,y,d,doorX,doorY,error=Art.standingPose(s)
  if x then
   local im=love.graphics.newImage("assets/generated/apartments-v1/"..id.."-floor.png")
   love.graphics.push();love.graphics.translate((i-1)%2*640+300,math.floor((i-1)/2)*512+270);love.graphics.scale(2)
   love.graphics.setShader();love.graphics.setColor(1,1,1,1)
   love.graphics.draw(im,Layout.X-x,Layout.Y-y,0,Layout.SCALE,Layout.SCALE)
   Art.draw(d,3,0,0,{},"loadwash",.6)
   love.graphics.setShader();love.graphics.setColor(.1,1,.2,.9);love.graphics.circle("line",doorX-x,doorY-y,2)
   love.graphics.pop();im:release();love.graphics.setColor(1,1,1,1)
   love.graphics.print(id.." / "..d.." / reach error "..string.format("%.1f",error),8+(i-1)%2*640,8+math.floor((i-1)/2)*512)
  end
 end
 love.graphics.setScissor()
 love.graphics.pop();save(apartments,"laundry-washer-contact");apartments:release()
 local colors=love.graphics.newCanvas(960,480)
 love.graphics.push("all");love.graphics.setCanvas(colors);love.graphics.clear(.13,.16,.18,1)
 for i,d in ipairs(R.order) do
  love.graphics.push();love.graphics.translate(120+(i-1)%4*240,210+math.floor((i-1)/4)*240);love.graphics.scale(1.7)
  Art.draw(d,2,0,0,{furColorway=(i-1)%6+1,overallsColorway=(i-1)%6+1},"unload",.5);love.graphics.pop()
 end
 love.graphics.pop();save(colors,"laundry-colorways");colors:release();Art.release()
 check("home_laundry_release",Art.cachedPhases()==0)
 local c=love.graphics.newCanvas(256,256);love.graphics.push("all");love.graphics.setCanvas(c);love.graphics.clear()
 Art.draw("northwest",3,128,180,{},"unload",.2);love.graphics.pop();c:release()
 check("home_laundry_reload",Art.cachedPhases()==1);Art.release()
 local f=assert(io.open(folder.."/laundry-registration.tsv","w"));f:write(table.concat(report,"\n"));f:close()
end
return Review
