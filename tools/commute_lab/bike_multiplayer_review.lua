-- Bounded review of observer-relative sprites using the production renderer,
-- network codec and independent host/guest camera objects.
local Review={}
local tau=math.pi*2
local function save(canvas,path)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();data:release()
end
function Review.run(check)
    local Art=require('src.commute.bike_art');local View=require('src.commute.first_person_renderer')
    local Camera=require('src.commute.camera');local FP=require('src.commute.first_person_camera')
    local Trip=require('src.commute.trip');local Codec=require('src.net.codec');local Bike=require('src.commute.motorcycle')
    local fixture=require('src.commute.tests.bike_multiplayer_view_test')
    local g=love.graphics;local output=assert(os.getenv('PICTURE_SHOP_BIKE_MULTIPLAYER_OUTPUT'))
    local world={size=512,height=function()return 0 end,supportHeight=function()return 0 end}
    local renderer={world=world,viewportWidth=640,viewportHeight=420,effectiveRadius=96,visible={},roadMeshes={},visibleProps={},
        structures={drawFirstPerson=function()end}}
    local art=Art.new();renderer.bikeArt=art
    local view=View.new(renderer)
    local format={{'VertexPosition','float',2},{'WorldHeight','float',1},{'VertexTexCoord','float',2}}
    local floor=g.newMesh(format,{{60,60,0,0,0},{150,60,0,1,0},{150,150,0,1,1},
        {60,60,0,0,0},{150,150,0,1,1},{60,150,0,0,1}},'triangles','static')
    view.meshes={{mesh=floor,color={.27,.32,.28,1}}}
    function renderer:shader(camera)
        FP.send(camera,view.shader);view.shader:send('sceneryRadius',96)
        view.shader:send('cameraCenter',{camera.centerX,camera.centerZ});return view.shader
    end
    local canvas=g.newCanvas(640,420);local gallery=g.newCanvas(1920,1260)
    local trip=fixture.fixture();local calls={};local draw=g.draw;local records={};local captureIndex=0
    g.draw=function(image,quad,...)
        local info=art:describe(image,quad)
        if info then local _,_,_,alpha=g.getColor();info.alpha=alpha;calls[#calls+1]=info end
        return draw(image,quad,...)
    end
    local function render(observer,mode,otherMode,label)
        local snapshot=assert(Codec.decode(assert(Codec.encode(Trip.snapshot(trip)))))
        local own=snapshot.participants[observer==1 and 'owner' or 'guest-1']
        local other=snapshot.participants[observer==1 and 'guest-1' or 'owner']
        local camera=Camera.new(own.rider.bike,world);camera:setViewport(640,420);camera.zoom=.9
        camera:setFirstPerson(mode=='first',own.rider.bike)
        local target=other.rider.bike;local expected
        if camera.firstPerson then
            camera.viewHeading=math.atan2(target.z-camera.centerZ,target.x-camera.centerX)
            camera.viewCos,camera.viewSin=math.cos(camera.viewHeading),math.sin(camera.viewHeading)
            camera.viewPitch=-.035;camera.roll=0;camera.focal=600
            local bearing=math.atan2(target.z-camera.centerZ,target.x-camera.centerX)
            expected=math.floor(((target.heading-bearing)%tau)/(tau/64)+.5)%64+1
        else
            camera:setOutsideMode(mode,own.rider.bike,true)
            if mode=='fixed' then camera.centerX,camera.centerZ=104,100;camera.yaw=0 end
            expected=math.floor((target.heading+math.rad(camera.yaw)+math.pi*.5)/(tau/64)+.5)%64+1
        end
        calls={};g.push('all');g.setCanvas({canvas,depth=true});g.origin();g.clear(.19,.25,.23,1,0,1)
        if camera.firstPerson then
            view:draw(renderer,camera,own.rider.bike,{
                {actor=own.rider.bike,localPlayer=true,presentation=own.presentation},
                {actor=target,localPlayer=false,presentation=other.presentation}})
        else
            art:draw(own.rider.bike,camera,world,false,own.presentation)
            art:draw(target,camera,world,false,other.presentation)
        end
        local actual=calls[#calls]
        local okay=#calls==(camera.firstPerson and 1 or 2) and actual and actual.frame==expected and actual.alpha==1
        records[#records+1]=('{"observer":%d,"camera":"%s","otherCamera":"%s","expectedFrame":%d,"frame":%d,"state":"%s","draws":%d,"alpha":%.1f}')
            :format(observer,mode,otherMode,expected,actual and actual.frame or 0,actual and actual.state or 'missing',#calls,actual and actual.alpha or 0)
        if label then
            g.setShader();g.setColor(.96,.92,.78);g.print(label,12,12)
            g.print(('Observer %d: %s / other player: %s / view %02d'):format(observer,mode,otherMode,expected),12,33)
        end
        g.pop()
        if label then
            captureIndex=captureIndex+1;save(canvas,output..('/scene-%02d.png'):format(captureIndex))
            g.push('all');g.setCanvas(gallery);g.setShader();g.setColor(1,1,1)
            draw(canvas,(captureIndex-1)%3*640,math.floor((captureIndex-1)/3)*420);g.pop()
        end
        return okay,actual
    end
    local okay,reason=xpcall(function()
        g.push('all');g.setCanvas(gallery);g.clear(.19,.25,.23,1);g.pop()
        for observer=1,2 do for _,mode in ipairs({'fixed','follow','first'}) do
            local all=true
            for frame=1,64 do
                local target=trip.participants[observer==1 and 'guest-1' or 'owner'].rider.bike
                target.heading=(frame-1)*tau/64
                local prior
                for _,otherMode in ipairs({'fixed','follow','first'}) do
                    local drawn,actual=render(observer,mode,otherMode)
                    all=all and drawn and (not prior or prior==actual.frame);prior=actual.frame
                end
            end
            check('multiplayer_native_observer_'..observer..'_'..mode..'_all64_views_and_three_peer_camera_choices',all)
        end end
        local a=trip.participants.owner.rider.bike;local b=trip.participants['guest-1'].rider.bike
        a.heading=0;b.heading=0
        check('multiplayer_native_first_person_back',render(1,'first','fixed','Other rider faces away from you'))
        b.heading=math.pi
        check('multiplayer_native_first_person_front',render(1,'first','follow','Other rider faces toward you'))
        b.heading=math.pi*.5
        check('multiplayer_native_first_person_side',render(1,'first','first','Other rider turns across your view'))
        b.heading=0
        check('multiplayer_native_guest_observes_hosts_front',render(2,'first','fixed','Guest looks back toward the host'))
        a.heading=math.pi
        check('multiplayer_native_guest_observes_hosts_back',render(2,'first','first','Host turns away from the guest'))
        a.heading=0
        check('multiplayer_native_third_person_peer_first_person',render(1,'fixed','first','Your third person / peer first person'))
        check('multiplayer_native_follow_peer_fixed',render(1,'follow','fixed','Your follow camera / peer fixed camera'))
        b.z=103
        check('multiplayer_native_offcenter_observer_angle',render(1,'first','fixed','Same heading, but rider is off to your right'))
        b.z=97
        check('multiplayer_native_opposite_offcenter_observer_angle',render(1,'first','follow','Same heading, but rider is off to your left'))
        b.z=100
        local A=require('src.commute.riding_animation')
        local samples={
            {'upright',{}},{'aeroMid',{speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2}},
            {'aero',{speed=Bike.BOOST_MAX_SPEED}},{'turnLeftMid',{lean=.225}},{'turnLeft',{lean=.3}},
            {'turnRightMid',{lean=-.225}},{'turnRight',{lean=-.3}},
            {'brakeMid',{speed=8,brakingWeight=.5}},{'brake',{speed=8,brakingWeight=1}},
            {'boostMid',{kind='boost',remaining=A.durations.boost*5/6}},{'boost',{kind='boost',remaining=A.durations.boost/2}},
            {'shiftMid',{kind='shift',remaining=A.durations.shift*5/6}},{'shift',{kind='shift',remaining=A.durations.shift/2}},
            {'impactMid',{impactPulse=Bike.IMPACT_DURATION*5/6,impactStrength=1}},
            {'impact',{impactPulse=Bike.IMPACT_DURATION/2,impactStrength=1}},
        }
        for _,sample in ipairs(samples) do
            local state,values=sample[1],sample[2]
            A.reset(b);b.speed,b.lean,b.impactPulse,b.impactStrength=values.speed or 0,values.lean or 0,values.impactPulse or 0,values.impactStrength or 0
            b.ridingAnimation.kind=values.kind or 'idle';b.ridingAnimation.remaining=values.remaining or 0
            b.ridingAnimation.brakingWeight=values.brakingWeight or 0;b.paintId='red'
            local drawn,actual=render(1,'first','first')
            check('multiplayer_native_replicated_'..state..'_uses_correct_64_view_action',drawn and actual.state==state)
        end
        save(gallery,output..'/observer-views.png')
        local file=assert(io.open(output..'/draw-coverage.json','wb'))
        file:write('{"draws":['..table.concat(records,',')..']}\n');file:close()
    end,debug.traceback)
    g.draw=draw;canvas:release();gallery:release();view:release();art:release();assert(okay,reason)
end
function Review.install()
    function love.load()
        local count=0;local function check(name,okay)assert(okay,name);count=count+1;print('PASS '..name)end
        require('src.commute.tests.bike_multiplayer_view_test').run(check)
        Review.run(check)
        print('BIKE_MULTIPLAYER_OK '..count..' checks; two observers, all64 views, nine camera pairings, all15 poses')
        love.event.quit(0)
    end
end
return Review
