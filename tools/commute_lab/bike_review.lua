-- Review actual runtime atlas selection, anchors and scale without loading saves.
local BikeArt=require('src.commute.bike_art')
local Camera=require('src.commute.camera')
local Review={}
function Review.install()
    local art,camera,captured
    local world={height=function() return 0 end,supportHeight=function() return 0 end}
    local output=assert(os.getenv('PICTURE_SHOP_BIKE_REVIEW_OUTPUT'))
    function love.load()
        love.window.setMode(1280,1280,{vsync=0,highdpi=false})
        art=BikeArt.new()
        camera=Camera.new({x=0,z=0},world)
        camera.yaw=0;camera.zoom=Camera.ZOOM_DEFAULT;camera.outsideMode='follow'
    end
    function love.draw()
        local g=love.graphics
        g.clear(.22,.29,.29,1)
        g.setColor(.94,.93,.80)
        g.print('Mounted rider v2 / actual BikeArt renderer / default camera zoom '..camera.zoom,16,12)
        for i,direction in ipairs(BikeArt.directions) do
            local x=((i-1)%4)*320;local y=math.floor((i-1)/4)*300+40
            g.setColor(.94,.93,.80);g.print(direction,x+12,y+8)
            g.setColor(.48,.6,.56);g.line(x+12,y+260,x+308,y+260)
            for _,parked in ipairs({true,false}) do
                local sx=x+(parked and 80 or 240)
                -- Only screen placement is overridden; heading selection, quad,
                -- runtime scale and ground-contact draw origin remain real.
                camera.screen=function() return sx,y+260 end
                art:draw({x=0,z=0,h=0,heading=-math.pi/2+(i-1)*math.pi/8},camera,world,parked)
                g.setColor(.83,.88,.81);g.print(parked and 'parked' or 'mounted',sx-27,y+274)
            end
        end
        if not captured then
            captured=true
            g.captureScreenshot(function(data)
                local bytes=data:encode('png');local f=assert(io.open(output,'wb'))
                f:write(bytes:getString());f:close();bytes:release();data:release()
                print('BIKE_NATIVE_REVIEW_OK '..output);love.event.quit(0)
            end)
        end
    end
    function love.quit() if art then art:release() end end
end
return Review
