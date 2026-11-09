local g=love.graphics
local root=assert(os.getenv('KEI_REVIEW_ROOT'))
local output=root..'/output/kei-scale-repair'
local function writePng(data,path)
    local png=data:encode('png');local file=assert(io.open(path,'wb'))
    file:write(png:getString());file:close();png:release()
end
local function bounds(data)
    local lo,hi=math.huge,-1
    for y=0,data:getHeight()-1 do for x=0,data:getWidth()-1 do
        local _,_,_,a=data:getPixel(x,y)
        if a>128/255 then lo=math.min(lo,y);hi=math.max(hi,y) end
    end end
    return hi-lo+1,hi
end
function love.load()
    local Art=require('src.commute.truck_art')
    local art=Art.new()
    local checks=0
    local function check(name,okay,detail)
        assert(okay,name..': '..(detail or 'failed'));checks=checks+1
        print('PASS '..name..' '..(detail or ''))
    end
    require('src.commute.tests.kei_turntable_scale_test').run(check)
    require('src.commute.tests.kei_steering_test').run(check)
    local actor={x=0,z=0,h=0,model='kei',heading=0}
    local before={}
    for _,kind in ipairs({'isometric','chase'}) do
        before[kind]={}
        for page=1,4 do before[kind][page]=g.newImage(
            ('output/kei-scale-repair/before/%s-64-%d.png'):format(kind,page)) end
    end
    local sprite=g.newCanvas(420,340)
    local composite=g.newCanvas(840,680)
    local stats={isometric={min=1000,max=0,frames={}},chase={min=1000,max=0,frames={}}}
    local function oldPitch(angle)
        local depth=1.76*math.abs(math.cos(angle))+.76*math.abs(math.sin(angle))
        local base=depth*29*math.sin(math.rad(32))/math.sin(math.rad(55))
            +2.30*22*math.cos(math.rad(32))/math.cos(math.rad(55))
        return math.max(.78,math.min(1.18,(depth*29+2.30*22)/base))
    end
    for step=0,119 do
        local angle=step*math.pi/60
        actor.heading=angle-math.pi/2
        g.setCanvas(composite);g.clear(.23,.27,.29,1)
        for row,kind in ipairs({'isometric','chase'}) do
            local camera={zoom=2,yaw=0,tilt=55,outsideMode=kind=='chase' and 'shoulder' or 'follow',
                screen=function()return 210,265 end}
            local frame=Art.frame(camera,actor.heading,'kei',kind)
            local _,quad,format=art.keiPages:get(kind,frame)
            for col=0,1 do
                g.setCanvas(sprite);g.clear(0,0,0,0);g.setColor(1,1,1,1)
                g.setBlendMode('alpha','alphamultiply')
                if col==0 then
                    local scale=format.scale*camera.zoom*.67
                    g.draw(before[kind][math.floor((frame-1)/16)+1],quad,210,265,0,scale,
                        scale*(kind=='isometric' and oldPitch(angle) or 1),format.anchorX,format.anchorY)
                else art:draw(actor,camera,{},true) end
                g.setCanvas()
                if col==1 then
                    local data=sprite:newImageData();local height,bottom=bounds(data);data:release()
                    local s=stats[kind];s.min=math.min(s.min,height);s.max=math.max(s.max,height)
                    s.frames[frame]=true
                end
                g.setCanvas(composite)
                g.setBlendMode('alpha','premultiplied')
                g.setColor(1,1,1,1);g.draw(sprite,col*420,(row-1)*340)
                g.setBlendMode('alpha','alphamultiply')
                local baseline=(row-1)*340+(kind=='isometric' and 300 or 264)
                g.setColor(.55,.65,.65,1);g.line(col*420+15,baseline,col*420+405,baseline)
                g.setColor(1,1,1,1)
                g.print((col==0 and 'PREVIOUS SIZING' or 'FIXED')..' / '..kind..' / '..(step*3)..' degrees',col*420+16,(row-1)*340+14)
            end
        end
        g.setCanvas();local data=composite:newImageData()
        writePng(data,('%s/rotation-%03d.png'):format(output,step));data:release()
    end
    for kind,s in pairs(stats) do
        local count=0;for _ in pairs(s.frames) do count=count+1 end
        -- At 2x zoom, linear filtering can move each curved alpha edge by a
        -- screen pixel despite identical source heights. Allow that rounding.
        check('rendered_'..kind..'_full_circle_height',s.max-s.min<=3,
            ('height=%d..%d, selected views=%d'):format(s.min,s.max,count))
        check('rendered_'..kind..'_all_selected_views',count==(kind=='isometric' and 40 or 39))
    end
    -- Exercise the production driving controller for a complete circle too.
    local Truck=require('src.commute.delivery_truck')
    local truck=Truck.new(256,256,0,'plain','kei')
    local world={supportHeight=function()return 0,'road' end,
        roads={sample=function()return 0,{width=20} end,blocked=function()return false end}}
    local turn,last=0,truck.heading
    for i=1,2400 do
        Truck.update(truck,{drive=1,steer=1},1/60,world)
        local delta=(truck.heading-last+math.pi)%(2*math.pi)-math.pi
        turn=turn+math.abs(delta);last=truck.heading
        if turn>=2*math.pi then break end
    end
    check('kei_driving_controller_completes_circle',turn>=2*math.pi)
    art:release();sprite:release();composite:release()
    for _,pages in pairs(before) do for _,im in ipairs(pages) do im:release() end end
    print(('KEI_ROTATION_REVIEW_OK: %d checks, 120 engine-rendered rotation frames'):format(checks))
    love.event.quit()
end
function love.errorhandler(message)
    print(debug.traceback(tostring(message),2));return function()return 1 end
end
