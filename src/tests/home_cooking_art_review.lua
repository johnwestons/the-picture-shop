local Review={}
function Review.run(check,folder)
 local Art=require("src.home_cooking_art");local R=require("src.home_cooking_registration")
 local function save(canvas,name)
  local data=canvas:newImageData();local bytes=data:encode("png")
  local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close();bytes:release();data:release()
 end
 local all=love.graphics.newCanvas(1280,2048);local failures={};local report={"direction\tframe\tscale\tvalid"}
 love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.clear(.13,.16,.18,1);love.graphics.pop()
 for row,direction in ipairs(R.order) do
  local strip=love.graphics.newCanvas(1280,256)
  love.graphics.push("all");love.graphics.setCanvas(strip);love.graphics.clear()
  for frame=1,4 do
   love.graphics.push();love.graphics.translate((frame-1)*320+160,210);love.graphics.scale(1.7)
   local c=Art.draw(direction,frame,0,0,{})
   love.graphics.pop();report[#report+1]=string.format("%s\t%d\t%.4f\t%s",direction,frame,c.scale,tostring(c.valid))
   if not c.valid then failures[#failures+1]=direction..frame end
   local replay=Art.contact(direction,Art.frame((frame-1)/R.fps+.001))
   check("home_cook_review_clock_"..direction..frame,replay.x==c.x and replay.y==c.y)
  end
  love.graphics.pop();save(strip,"cook-"..direction.."-assembled")
  love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.setShader();love.graphics.setColor(1,1,1,1)
  love.graphics.draw(strip,0,(row-1)*256);love.graphics.print(direction,8,(row-1)*256+8);love.graphics.pop();strip:release()
  check("home_cook_review_cache_bound_"..direction,Art.cachedDirections()<=4)
 end
 save(all,"cook-all-directions");all:release();Art.release()
 local Fixtures=require("src.tests.home_dining_test");local Layout=require("src.home_layouts")
 local Catalog=require("src.home_furniture_catalog");local Furniture=require("src.home_furniture")
 local Navigation=require("src.navigation");local placements={"apartment\tstove\tactor\twalkable\tx\ty"}
 local stoveSheet=love.graphics.newCanvas(1280,512)
 love.graphics.push("all");love.graphics.setCanvas(stoveSheet);love.graphics.clear(.13,.16,.18,1)
 for apartmentIndex,id in ipairs(require("src.home_catalog").ORDER) do
  local state,player=Fixtures.fresh(id);local sx,sy=Layout.kitchenPower(state)
  local item={id=1,kind="stove",location="floor",x=sx,y=sy,direction="south"};state.home.furniture.items={item}
  for _,stoveDirection in ipairs(R.order) do
   item.direction=stoveDirection
   for index,direction in ipairs(R.order) do
    local x,y=Art.standingPose(state,direction,item)
    check("home_cook_stance_"..id.."_"..stoveDirection.."_"..direction,x~=nil)
    local clear=Navigation.isWalkable({getData=function()return Layout.mask(state.home.apartmentId) end},x,y,Furniture.obstacles(state))
    placements[#placements+1]=string.format("%s\t%s\t%s\t%s\t%.1f\t%.1f",id,stoveDirection,direction,tostring(clear),x-sx,y-sy)
    if apartmentIndex==1 and stoveDirection=="south" then
     love.graphics.push();love.graphics.translate(160+(index-1)%4*320,220+math.floor((index-1)/4)*256);love.graphics.scale(1.7)
     if y<sy then Art.draw(direction,2,x-sx,y-sy,{},true) end
     require("src.home_furniture_art").draw({kind="stove",direction=stoveDirection,x=0,y=0})
     local px,py=Art.stoveTop(item);Art.drawPan(stoveDirection,px-sx,py-sy)
     if y>=sy then Art.draw(direction,2,x-sx,y-sy,{},true) end
     love.graphics.pop();love.graphics.setShader();love.graphics.setColor(1,1,1,1)
     love.graphics.print(direction.." / walkable: "..tostring(clear),8+(index-1)%4*320,8+math.floor((index-1)/4)*256)
    end
   end
  end
 end
 love.graphics.pop();save(stoveSheet,"cook-stove-contact");stoveSheet:release();Art.release()
 local placementFile=assert(io.open(folder.."/cooking-stove-placement.tsv","w"));placementFile:write(table.concat(placements,"\n"));placementFile:close()
 local file=assert(io.open(folder.."/cooking-registration.tsv","w"));file:write(table.concat(report,"\n"));file:close()
 check("home_cook_review_release",Art.cachedDirections()==0)
 check("home_cook_review_all_contacts",#failures==0,table.concat(failures,", "))
end
return Review
