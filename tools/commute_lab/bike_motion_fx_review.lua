local Review={}
local function save(canvas,path)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();data:release()
end
local function scenes(check)
    local g=love.graphics;local Art=require('src.commute.bike_art');local Camera=require('src.commute.camera')
    local Particles=require('src.commute.bike_particles');local output=assert(os.getenv('PICTURE_SHOP_BIKE_FX_OUTPUT'))
    local cases={
        {label='Paved road / riding',surface='asphalt',speed=8,engine=true},
        {label='Dirt trail / riding',surface='dirt',speed=8,engine=true},
        {label='Engine idling / stopped tires',surface='asphalt',speed=0,engine=true},
        {label='Engine off / stopped tires',surface='asphalt',speed=0,engine=false},
    }
    local art=Art.new();local sheet=g.newCanvas(1280,720);local panel=g.newCanvas(640,360)
    for _,scene in ipairs(cases) do
        scene.world={size=512,height=function()return 0 end,supportHeight=function()return 0 end}
        scene.world.roads={nearest=function()return 0,{surface=scene.surface,width=6}end}
        scene.bike={x=100,z=100,h=0,speed=scene.speed,heading=0,lean=0,distance=0,grounded=true,throttle=.65}
        scene.camera=Camera.new(scene.bike,scene.world);scene.camera:setViewport(640,360);scene.camera.zoom=1.6
        scene.fx=Particles.new();scene.fx:prewarm()
    end
    for frame=1,96 do
        g.push('all');g.setCanvas(sheet);g.clear(.1,.14,.14,1);g.pop()
        for index,scene in ipairs(cases) do
            local b,c,fx=scene.bike,scene.camera,scene.fx;local dt=1/30
            b.x=b.x+b.speed*dt;b.distance=b.distance+b.speed*dt
            c.centerX,c.centerZ=b.x-1,b.z
            fx:advance(dt);fx:emit('bike',b,scene.world,dt,nil,scene.engine,true)
            g.push('all');g.setCanvas({panel,depth=true});g.origin();g.setDepthMode('always',false);g.setShader()
            if scene.surface=='dirt' then g.clear(.36,.31,.23,1,0,1) else g.clear(.20,.24,.24,1,0,1) end
            g.setColor(.8,.77,.64,.10);g.setLineWidth(1)
            for x=math.floor(b.x)-6,math.floor(b.x)+6 do
                local ax,ay=c:screen(x,b.z-6,0);local bx,by=c:screen(x,b.z+6,0);g.line(ax,ay,bx,by)
            end
            fx:draw(c,96,51200);g.setDepthMode('always',false)
            art:draw(b,c,scene.world,false)
            g.setColor(.96,.92,.79);g.print(scene.label,16,16)
            local stats=fx:stats();g.setColor(.8,.83,.77)
            g.print(('Dust %d / exhaust %d'):format(stats.dust,stats.exhaust),16,38)
            g.pop()
            g.push('all');g.setCanvas(sheet);g.setColor(1,1,1,1)
            g.draw(panel,(index-1)%2*640,math.floor((index-1)/2)*360);g.pop()
        end
        save(sheet,output..('/particles-%03d.png'):format(frame))
    end
    check('bike_fx_native_trail_is_dustier_than_paved_over_the_same_motion',cases[2].fx.totalDust>cases[1].fx.totalDust*4)
    check('bike_fx_native_idling_has_smoke_but_no_tire_dust',cases[3].fx.totalExhaust>0 and cases[3].fx.totalDust==0)
    check('bike_fx_native_engine_off_stationary_has_no_particles',cases[4].fx:stats().active==0)
    save(sheet,output..'/particles-preview.png')
    for _,scene in ipairs(cases) do scene.fx:release() end
    sheet:release();panel:release();art:release()
end
function Review.install()
    function love.load()
        local count=0;local function check(name,okay)assert(okay,name);count=count+1;print('PASS '..name)end
        for _,name in ipairs({'bike_particles','bike_tire_motion','bike_action_pose'}) do
            require('src.commute.tests.'..name..'_test').run(check)
        end
        require('tools.commute_lab.bike_tire_motion_review').run(check)
        scenes(check)
        print('BIKE_MOTION_FX_OK '..count..' checks; native tire pixels and 96 particle scene frames')
        love.event.quit(0)
    end
end
return Review
