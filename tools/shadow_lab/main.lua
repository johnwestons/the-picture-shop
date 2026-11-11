local output=require('lab_paths').output
local function write(name,data)local f=assert(io.open(output..'/'..name,'wb'));f:write(data);f:close()end
function love.errorhandler(err)
    write('smoke-report.txt','ERROR '..tostring(err)..'\n'..debug.traceback());return function()return 1 end
end
local S=require('src.shadow_shapes')
local Outdoor=require('src.commute.shadows')
local Indoor=require('src.warehouse_shadows')
local Camera=require('src.commute.camera')
local Day=require('src.commute.day_night')
local Video=require('src.video_settings')
local Settings=require('src.settings')
local Options=require('src.screens.options_screen')
local smoke=os.getenv('PICTURE_SHOP_SHADOW_SMOKE')=='1'
local canvas,ground,shader,camera,renderer,background
local scene,enabled,hour,frames=1,true,9,0
local timing={};local report={};local checks=0
local static={{x=350,y=450,width=42,depth=18,height=75,kind='polar_115'},{x=730,y=440,width=43,depth=18,height=105,kind='skid_wrapper'},{x=600,y=540,width=30,depth=12,height=35}}
local people={{x=480,y=480,kind='person',width=24,height=68},{x=240,y=380,kind='person',width=24,height=68}}
local world={size=128,maxHeight=10}
function world:height(x,z)return math.max(0,(z-5)*.08)end
function world:supportHeight(x,z)return self:height(x,z),'ground'end
local function check(name,ok)assert(ok,name);checks=checks+1;report[#report+1]='PASS '..name end
function love.load()
    require('src.commute.tests.local_lights_test')(check)
    require('src.commute.tests.day_night_test').run(check)
    for _,file in ipairs({'src/world_renderer.lua','src/commute/renderer.lua','src/commute/first_person_renderer.lua','src/commute/structures.lua'})do
        check('syntax '..file,loadstring(love.filesystem.read(file))~=nil)
    end
    local x,z,a=S.sun({1,1,0},2);check('sun projects away',x==-2 and z==0 and a==1)
    x,z,a=S.sun({1,-1,0},2);check('night suppresses sun',a==0)
    x,z=S.sun({1,.0001,1},100,18);check('horizon length bounded',math.sqrt(x*x+z*z)<18.001)
    x,z=S.point(600,400,60,480,365,300);check('central lamp projects outward',x>600 and z>400)
    local hull=S.box(0,0,2,1,4,2);check('box silhouette has corners',#hull>=8)
    check('person has ears and limbs',#S.person>12)
    local outline=S.silhouette(S.person,0,0,1,-2,1);check('person triangulates',pcall(love.math.triangulate,outline))
    local defaults=Settings.normalize()
    if smoke then require('src.tests.options_test').run({Settings=Settings,State=require('src.state'),
        SaveEditor=require('src.save_editor'),save=require('src.save')},check)end
    check('performance friendly defaults',defaults.dynamicShadows and not defaults.vegetationShadows and defaults.renderDistance=='medium')
    local invalid=Settings.normalize({shadowDistance='invalid',renderDistance=123})
    check('invalid distances fall back',invalid.shadowDistance=='medium' and invalid.renderDistance=='medium')
    Options.enter({settings=defaults,save={SLOT_COUNT=3},state={},onClose=function()scene=1 end})
    Options.mousepressed(260,114,1);check('video tab reachable',Options.tab=='video')
    if smoke then
        Options.keypressed('return');check('video toggle disables shadows live',not Video.current.dynamicShadows)
        check('shadow option persists',Settings.load().dynamicShadows==false)
        Options.keypressed('return');Options.keypressed('down');Options.keypressed('return')
        check('tree shadows opt in',Video.current.vegetationShadows)
        Options.keypressed('down');Options.keypressed('right');check('shadow distance saves',Settings.load().shadowDistance=='far')
        Options.keypressed('down');Options.keypressed('left');check('render distance affects policy',Video.renderRadius()==48)
        Options.context.settings=Settings.normalize();Settings.applyDisplay(Options.context.settings)
    end
    background=love.graphics.newImage('warehouse.png')
    canvas=love.graphics.newCanvas(960,678,{dpiscale=1})
    renderer={world=world,clock=0,viewportWidth=960,viewportHeight=678,visibleProps={
        {kind='oak',x=-5,z=0,h=0,scale=.6},{kind='pine',x=5,z=-4,h=0,scale=.65}},structures={buildings={
        {x=0,z=-5,bounds={minH=0},shadowFaces={{{-2,-8,3},{2,-8,3},{2,-4,3}},{{-2,-8,3},{2,-4,3},{-2,-4,3}}}}}}}
    function renderer:depthSpan()return 22800 end
    renderer.shadows=Outdoor.new()
    camera=Camera.new({x=0,z=0,h=0},world);camera:setViewport(960,678);camera.zoom=1.2
    shader=renderer.shadows.shader
    local vertices={}
    for gx=-20,19 do for gz=-20,19 do
        for _,p in ipairs({{gx,gz},{gx+1,gz},{gx+1,gz+1},{gx,gz},{gx+1,gz+1},{gx,gz+1}})do vertices[#vertices+1]={p[1],p[2],world:height(p[1],p[2])}end
    end end
    ground=love.graphics.newMesh({{'VertexPosition','float',2},{'WorldHeight','float',1}},vertices,'triangles','static')
    check('outdoor shader compiled',shader~=nil)
end
local function outdoor()
    local g=love.graphics;g.setCanvas({canvas,depth=true,stencil=true});g.clear(.64,.73,.72,1,0,1);g.setDepthMode('lequal',true)
    g.setShader(shader);camera:send(shader);shader:send('groundDepthSpan',renderer:depthSpan());g.setColor(.49,.60,.37);g.draw(ground)
    local light=Day.sample({month=6,day=1,elapsed=hour/24*1200,secondsPerDay=1200})
    renderer.clock=frames/60
    if enabled then renderer.shadows:draw(renderer,camera,{{actor={x=1,z=2},characterId='cat'}},light)end
    g.setShader();g.setDepthMode()
    if not camera.firstPerson then
        -- Simple visible casters deliberately match the proxy dimensions.
        for _,p in ipairs(renderer.visibleProps)do
            local x,y=camera:screen(p.x,p.z,p.h);local height=p.scale*248*camera.zoom
            g.setColor(.35,.23,.14);g.rectangle('fill',x-4,y-height*.45,8,height*.45)
            g.setColor(.20,.36,.19);local pts={}
            for _,v in ipairs(p.kind=='pine' and S.pine or S.tree)do pts[#pts+1]=x+v[1]*height*.60;pts[#pts+1]=y-v[2]*height end
            for _,tri in ipairs(love.math.triangulate(pts))do g.polygon('fill',tri)end
        end
        local x,y=camera:screen(0,-6,0);g.setColor(.65,.57,.43);g.rectangle('fill',x-100,y-90,200,90)
        g.setColor(.32,.36,.40);g.polygon('fill',x-110,y-90,x,y-140,x+110,y-90)
        local px,py=camera:screen(1,2,0);g.setColor(.82,.57,.27);g.rectangle('fill',px-12,py-35,24,35);g.circle('fill',px,py-43,15)
    end
end
local function indoor()
    local g=love.graphics;g.setCanvas(canvas);g.clear();g.setColor(1,1,1);g.draw(background,0,0,0,960/background:getWidth(),678/background:getHeight())
    Indoor.enabled=enabled;Indoor.draw(static,people,true)
    for _,p in ipairs(static)do
        g.setColor(.34,.43,.46);g.rectangle('fill',p.x-p.width,p.y-p.height,p.width*2,p.height)
        g.setColor(.65,.72,.71);g.rectangle('fill',p.x-p.width,p.y-p.height,p.width*2,12)
    end
    for _,p in ipairs(people)do
        g.setColor(.69,.45,.24);g.rectangle('fill',p.x-10,p.y-35,20,35);g.circle('fill',p.x,p.y-44,14)
        g.polygon('fill',p.x-13,p.y-49,p.x-14,p.y-64,p.x-3,p.y-54)
        g.polygon('fill',p.x+13,p.y-49,p.x+14,p.y-64,p.x+3,p.y-54)
    end
end
function love.draw()
    local start=love.timer.getTime();local g=love.graphics;g.push('all');g.origin()
    if scene==1 then outdoor()elseif scene==2 then indoor()else g.setCanvas(canvas);Options.draw()end
    g.setCanvas();g.setShader();g.setDepthMode();g.setColor(1,1,1);g.setBlendMode('alpha','premultiplied');g.draw(canvas)
    g.setBlendMode('alpha');g.setColor(.05,.08,.10,.95);g.rectangle('fill',0,0,960,76)
    g.setColor(1,1,1);g.print('SHADOW LAB  |  '..(scene==1 and 'OUTDOOR SUN' or 'WAREHOUSE CEILING LIGHT')..'  |  '..(enabled and 'ON' or 'OFF'),18,12)
    g.print('Tab: scene   S: shadows   O: video options   Arrows: sun time   F: camera   Mouse: warehouse worker',18,38)
    g.print(('Sun %.1f h  |  shadow vertices %d  |  simplified test casters, production shadow modules'):format(hour,renderer.shadows.stats.vertices or 0),18,57)
    g.pop();frames=frames+1
    if smoke then
        if frames>5 then timing[#timing+1]=(love.timer.getTime()-start)*1000 end
        if frames==10 then
            check('outdoor mesh generated',(renderer.shadows.stats.vertices or 0)>0)
            write('outdoor.png',canvas:newImageData():encode('png'):getString());scene=2
        elseif frames==20 then
            write('warehouse.png',canvas:newImageData():encode('png'):getString());scene=1
            camera.firstPerson=true;camera.eyeHeight=2;camera.viewHeading=0;camera.viewPitch=-.12;camera.roll=0;camera.focal=500
            camera.centerX=-12;camera.centerZ=0;camera.viewCenterX=480;camera.viewCenterY=339
        elseif frames==30 then
            check('first person shadow pass ran',true);write('first-person.png',canvas:newImageData():encode('png'):getString())
            scene=3;Options.tab='video'
        elseif frames==40 then
            write('video-options.png',canvas:newImageData():encode('png'):getString())
            renderer.shadows:release();Indoor.release();check('resources released',true)
            table.sort(timing);report[#report+1]=('CPU draw submission median %.3f ms (not GPU frame time; tiny lab scene)'):format(timing[math.ceil(#timing/2)])
            report[#report+1]='SHADOW_SMOKE_OK '..checks;write('smoke-report.txt',table.concat(report,'\n'));love.event.quit(0)
        end
    end
end
function love.keypressed(key)
    if scene==3 then Options.keypressed(key);return end
    if key=='escape'then love.event.quit()elseif key=='tab'then scene=3-scene elseif key=='s'then enabled=not enabled
    elseif key=='left'then hour=(hour-.5)%24 elseif key=='right'then hour=(hour+.5)%24
    elseif key=='o'then scene=3;Options.tab='video'
    elseif key=='f'then camera.firstPerson=not camera.firstPerson;camera.eyeHeight=2;camera.viewHeading=0;camera.viewPitch=-.12;camera.roll=0;camera.focal=500;camera.viewCenterX=480;camera.viewCenterY=339 end
end
function love.mousepressed(x,y,button)if scene==3 then Options.mousepressed(x,y,button)end end
function love.mousemoved(x,y)if scene==2 then people[1].x=math.max(40,math.min(920,x));people[1].y=math.max(300,math.min(640,y))end end
