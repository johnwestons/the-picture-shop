-- Staged art review only. This does not enable incomplete action coverage in game.
local Review={}
function Review.run(check)
    local folder=os.getenv("PICTURE_SHOP_HOME_ART_REVIEW");if not folder then return end
    require("src.tests.home_cooking_art_review").run(check,folder)
    require("src.tests.home_wipe_art_review").run(check,folder)
    local body=love.graphics.newImage("assets/generated/home-routines-v2/sweep-east-empty-hands.png")
    local broom=love.graphics.newImage("assets/generated/home-routines-v2/broom-eight-directions-long-shaft.png")
    local propQuad=love.graphics.newQuad(0,0,384,512,broom:getDimensions())
    local shader=love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 s){vec4 p=Texel(t,uv);if(p.a<.18)discard;return p*c;}]])
    local registration={
        {180,478,185,274,290,334},{183,478,190,282,280,341},
        {183,478,186,284,256,346},{188,478,185,287,224,347},
        {182,446,198,250,288,302},{178,446,244,269,306,311},
        {174,446,268,282,316,317},{182,446,192,250,289,304},
    }
    local strip=love.graphics.newCanvas(1024,256);local gallery=love.graphics.newCanvas(1024,256)
    local function draw(i,x,y,zoom,validate)
        local r=registration[i];local bodyScale=.19;local propScale=.17
        local hx,hy=(r[3]-r[1])*bodyScale,(r[4]-r[2])*bodyScale
        local rotation=math.atan2(r[6]-r[4],r[5]-r[3])-math.atan2(281,150)
        local c,s=math.cos(rotation),math.sin(rotation)
        local function rotateY(dx,dy)return dx*s+dy*c end
        -- Both hands determine the shaft line. Slide the grip along that line
        -- so the bristle contact stays on the floor instead of bobbing in air.
        local t=(rotateY(280-74,475-34)+hy/propScale)/rotateY(150,281)
        local ox,oy=74+150*t,34+281*t
        local lower=t+math.sqrt((r[5]-r[3])^2+(r[6]-r[4])^2)*bodyScale/propScale/math.sqrt(150^2+281^2)
        if validate then check("home_sweep_review_grips_on_shaft_"..i,t>=0 and lower<=1.06,string.format("%.3f %.3f",t,lower)) end
        love.graphics.push();love.graphics.translate(x,y);love.graphics.scale(zoom)
        love.graphics.setShader(shader);love.graphics.setColor(1,1,1,1)
        love.graphics.draw(broom,propQuad,hx,hy,rotation,propScale,propScale,ox,oy)
        local quad=love.graphics.newQuad((i-1)%4*384,math.floor((i-1)/4)*512,384,512,body:getDimensions())
        love.graphics.draw(body,quad,0,0,0,bodyScale,bodyScale,r[1],r[2]);quad:release()
        love.graphics.pop()
    end
    love.graphics.push("all");love.graphics.setCanvas(strip);love.graphics.clear()
    for i=1,4 do draw(i,(i-1)*256+96,210,2,true) end
    love.graphics.setCanvas(gallery);love.graphics.clear(.13,.16,.18,1)
    for i=1,4 do draw(i,(i-1)*256+96,210,2) end
    love.graphics.pop()
    for name,canvas in pairs({["sweep-east-strip"]=strip,["sweep-east-contact"]=gallery}) do
        local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close()
        bytes:release();data:release();canvas:release()
    end
    body:release();broom:release();propQuad:release();shader:release()
    local Art=require("src.home_sweep_art");local Registration=require("src.home_sweep_registration")
    local all=love.graphics.newCanvas(1280,2048);local report={"direction\tframe\tupper_grip\tlower_grip\tvalid"};local failures={}
    local function save(canvas,name)
        local data=canvas:newImageData();local bytes=data:encode("png")
        local file=assert(io.open(folder.."/"..name..".png","wb"));file:write(bytes:getString());file:close();bytes:release();data:release()
    end
    love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.clear(.13,.16,.18,1);love.graphics.pop()
    for row,direction in ipairs(Registration.order) do
        local strip=love.graphics.newCanvas(1280,256)
        love.graphics.push("all");love.graphics.setCanvas(strip);love.graphics.clear()
        for frame=1,4 do
            love.graphics.push();love.graphics.translate((frame-1)*320+160,210);love.graphics.scale(1.7)
            local c=Art.draw(direction,frame,0,0,{})
            love.graphics.pop()
            report[#report+1]=string.format("%s\t%d\t%.3f\t%.3f\t%s",direction,frame,c.upper,c.lower,tostring(c.valid))
            if not c.valid then failures[#failures+1]=direction..frame end
        end
        love.graphics.pop();save(strip,"sweep-"..direction.."-assembled")
        love.graphics.push("all");love.graphics.setCanvas(all);love.graphics.setShader();love.graphics.setColor(1,1,1,1)
        love.graphics.draw(strip,0,(row-1)*256);love.graphics.print(direction,8,(row-1)*256+8);love.graphics.pop();strip:release()
    end
    save(all,"sweep-all-directions");all:release();Art.release()
    local file=assert(io.open(folder.."/registration.tsv","w"));file:write(table.concat(report,"\n"));file:close()
    check("home_sweep_all_direction_grips_review",#failures==0,table.concat(failures,", "))
end
return Review
