-- Native draw-path and physics acceptance, without opening a game save.
local Art=require('src.commute.bike_art')
local Camera=require('src.commute.camera')
local Bike=require('src.commute.motorcycle')
local Review={}
local function save(canvas,path)
    local pixels=canvas:newImageData();local png=pixels:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();pixels:release()
end
function Review.install()
    function love.load()
        love.window.setMode(1280,880,{vsync=0,highdpi=false})
        local count=0
        local function check(name,okay)assert(okay,name);count=count+1;print('PASS '..name)end
        for _,name in ipairs({'camera','follow_camera','first_person','bike_art','direction',
            'bike_pitch','bike_pitch_visual','ride_smoothing','motorcycle','controls','bike_paint'}) do
            require('src.commute.tests.'..name..'_test').run(check)
        end
        local world={height=function()return 0 end,supportHeight=function()return 0 end}
        local actor=Bike.new(0,0,0);actor.h=0
        local camera=Camera.new(actor,world)
        local art=Art.new();local g=love.graphics
        local output=assert(os.getenv('PICTURE_SHOP_BIKE_TURNING_OUTPUT'))
        local denseCount=Art.UPRIGHT_FRAME_COUNT
        local canvas=g.newCanvas(1600,math.ceil(denseCount/8)*220)
        g.push('all');g.setCanvas(canvas);g.clear(.13,.19,.20,1)
        for i=1,denseCount do
            local left,top=(i-1)%8*200,math.floor((i-1)/8)*220
            camera.screen=function()return left+100,top+184 end
            actor.heading=-math.pi*.5+(i-1)*math.pi*2/denseCount
            art:draw(actor,camera,world,false)
            g.setColor(.95,.92,.78)
            g.print(('Drawn view %02d / %g deg'):format(i,(i-1)*360/denseCount),left+8,top+10)
            local dx,dz=math.cos(actor.heading),math.sin(actor.heading)
            g.setColor(.4,.85,.75);g.line(left+100,top+204,left+100+dx*23,top+204+dz*14)
        end
        g.pop();save(canvas,output..('/native-%d-views.png'):format(denseCount));canvas:release()
        -- Sequential native frames expose angular stepping and registration.
        local frames=g.newCanvas(320,320)
        camera.screen=function()return 160,270 end
        for i=1,denseCount*2 do
            actor.heading=-math.pi*.5+(i-1)*math.pi/denseCount
            g.push('all');g.setCanvas(frames);g.clear(.13,.19,.20,1)
            art:draw(actor,camera,world,false);g.pop()
            save(frames,output..('/native-turn-%03d.png'):format(i))
        end
        frames:release();art:release()
        print(('BIKE_TURNING_OK %d checks; %d-view contact sheet and %d native turn frames'):format(count,denseCount,denseCount*2))
        love.event.quit(0)
    end
end
return Review
