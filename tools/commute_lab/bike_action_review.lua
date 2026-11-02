-- Deterministic native renderer review of the two previously snapping overlaps.
local Bike=require('src.commute.motorcycle')
local Art=require('src.commute.bike_art')
local Camera=require('src.commute.camera')
local Copy=require('src.save_schema').copy
local Review={}
local times={.1,.25,.4,.6,.78,.86,1,1.12}
function Review.install()
    local art,camera,captured;local rows={}
    local world={height=function()return 0 end,supportHeight=function()return 0 end,
        roads={nearest=function()return 0,{width=6}end,blocked=function()return false end}}
    function love.load()
        love.window.setMode(1600,560,{vsync=0,highdpi=false})
        art=Art.new();camera=Camera.new({x=0,z=0},world);camera.yaw=0;camera.zoom=1.35
        for row=1,2 do
            local bike=Bike.new(100,100,0);bike.transmission='manual';bike.speed=1
            if row==2 then assert(Bike.shift(bike,1)) end
            local elapsed=0;local shifted=row==2;rows[row]={}
            for _,target in ipairs(times) do
                while elapsed<target-1e-8 do
                    if row==1 and elapsed>=.2-1e-8 and not shifted then
                        assert(Bike.shift(bike,1));shifted=true
                    end
                    local dt=math.min(1/120,target-elapsed)
                    Bike.update(bike,{throttle=1,boost=row==1 or elapsed>=.1-1e-8},dt,world)
                    elapsed=elapsed+dt
                end
                rows[row][#rows[row]+1]=Copy(bike)
            end
        end
    end
    function love.draw()
        local g=love.graphics;g.clear(.22,.29,.29,1)
        for row,samples in ipairs(rows) do
            local y=(row-1)*280
            g.setColor(.95,.91,.78)
            g.print(row==1 and 'Boost at 0s; physical shift at 0.2s — shift pose waits'
                or 'Physical shift at 0s; boost at 0.1s — boost pose waits',12,y+10)
            for i,bike in ipairs(samples) do
                local x=(i-1)*200+100
                camera.screen=function()return x,y+240 end
                art:draw(bike,camera,world,false)
                local kind,weight=Art.action(bike)
                g.setColor(.95,.91,.78);g.print(('%0.2fs / gear %d'):format(times[i],bike.gear),x-88,y+40)
                g.print(('%s %.2f'):format(kind or 'idle',weight),x-88,y+58)
            end
        end
        if not captured then
            captured=true
            g.captureScreenshot(function(data)
                local output=assert(os.getenv('PICTURE_SHOP_BIKE_REVIEW_OUTPUT'))
                local f=assert(io.open(output,'wb'));local bytes=data:encode('png')
                f:write(bytes:getString());f:close();bytes:release();data:release()
                print('BIKE_ACTION_SEQUENCE_CAPTURE '..output);love.event.quit(0)
            end)
        end
    end
    function love.quit()if art then art:release()end end
end
return Review
