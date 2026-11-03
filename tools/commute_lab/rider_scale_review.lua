-- Native production-renderer review: every mounted view, walking counterpart,
-- normal outfit and dressing pose share the same camera zoom and foot baseline.
local Review={}
function Review.install()
    local BikeArt=require('src.commute.bike_art')
    local Camera=require('src.commute.camera')
    local Assets=require('src.character_assets')
    local Presentation=require('src.commute.presentation')
    local Scale=require('src.commute.rider_scale')
    local Config=require('src.config')
    local output=assert(os.getenv('PICTURE_SHOP_RIDER_SCALE_OUTPUT'))
    local world={height=function()return 0 end,supportHeight=function()return 0 end}
    local art,camera,canvas,captured
    local appearance={character='rabbit-worker',furColorway=1,overallsColorway=1}
    local poses={'suit_on','zip_up','boots_gloves','helmet_on'}
    local W,H=1920,1040
    function love.load()
        local count=0
        require('src.commute.tests.rider_scale_test').run(function(name,okay)
            assert(okay,name);count=count+1;print('PASS '..name)
        end)
        print('RIDER_SCALE_TEST_OK '..count..' checks; no saves accessed')
        love.window.setMode(1280,694,{vsync=0,highdpi=false})
        require('src.image_loader').setEnabled(false)
        Assets.load();art=BikeArt.new()
        camera=Camera.new({x=0,z=0},world);camera.yaw=0;camera.zoom=Camera.ZOOM_DEFAULT
        canvas=love.graphics.newCanvas(W,H)
    end
    function love.draw()
        local g=love.graphics
        if not captured then
            g.push('all');g.setCanvas(canvas);g.clear(.16,.21,.22,1)
            g.setColor(.96,.94,.82)
            g.print('RIDER SCALE / production sprites and renderers / all 16 bike views / shared zoom '..camera.zoom,20,14)
            g.print('Each cell: old suited | mounted (unchanged) | corrected suited | normal clothes | dressing. Lines are the same ground baseline.',20,35)
            Assets.beginFrame()
            for i,direction in ipairs(BikeArt.directions) do
                local x=((i-1)%4)*480;local y=math.floor((i-1)/4)*240+65
                local baseline=y+181
                local actor={x=0,z=0,h=0,heading=-math.pi/2+(i-1)*math.pi/8,speed=0,distance=0}
                g.setColor(.96,.94,.82);g.print(direction,x+12,y+6)
                g.setColor(.35,.46,.45);g.line(x+8,baseline,x+472,baseline)
                local function foot(at,outfit,visual)
                    camera.screen=function()return x+at,baseline end
                    assert(Presentation.world(Assets,actor,camera,world,{outfit=outfit},appearance,visual,0))
                end
                local corrected=Scale.BODY_HEIGHT
                Scale.BODY_HEIGHT=Config.player.drawScale*.7*Config.characterRendering.referenceHeight
                foot(38,'geared')
                Scale.BODY_HEIGHT=corrected
                camera.screen=function()return x+140,baseline end
                art:draw(actor,camera,world,false)
                foot(250,'geared')
                foot(340,'normal')
                foot(430,'geared',{pose=poses[(i-1)%4+1],progress=.5})
                g.setColor(.78,.84,.79)
                for n,label in ipairs({'old','mounted','suited','normal','gear'}) do
                    g.print(label,x+({23,114,229,320,416})[n],baseline+12)
                end
            end
            Assets.endFrame();g.pop()
            local data=canvas:newImageData();local bytes=data:encode('png')
            local file=assert(io.open(output,'wb'));file:write(bytes:getString());file:close()
            bytes:release();data:release();captured=true
            print('RIDER_SCALE_NATIVE_REVIEW_OK '..output)
            love.event.quit(0)
        end
        g.setColor(1,1,1);g.draw(canvas,0,0,0,1280/W,1280/W)
    end
    function love.quit()
        if art then art:release() end
        if canvas then canvas:release() end
        Assets.releaseAll()
    end
end
return Review
