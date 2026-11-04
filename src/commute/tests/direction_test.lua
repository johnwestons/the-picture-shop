-- Validate authored-view selection independently of pixel contents. The atlas
-- visual audit verifies physical facing; these checks protect its runtime wiring.
local Camera=require('src.commute.camera')
local FP=require('src.commute.first_person_camera')
local Art=require('src.commute.bike_art')
local Normal=require('src.commute.normal_art')
local Bike=require('src.commute.motorcycle')
local Rider=require('src.commute.rider')
local Trip=require('src.commute.trip')
local C=require('src.commute.runtime')
local Test={}
local tau=2*math.pi
local world={size=512,height=function()return 0 end,supportHeight=function()return 0 end,
    roads={nearest=function()return 0,{width=8} end,blocked=function()return false end}}
local function frameFromVector(right,forward,count)
    -- Atlas starts with the back of a northbound bike. Projection forward is
    -- therefore negative atlas Y, rather than screen-right/world-east frame 1.
    return math.floor((math.atan2(right,forward)+tau+math.pi/count)/(tau/count))%count+1
end
local names16={'north','north-northeast','northeast','east-northeast',
    'east','east-southeast','southeast','south-southeast','south','south-southwest',
    'southwest','west-southwest','west','west-northwest','northwest','north-northwest'}
local function cameraFrame16(camera,heading)
    local direction=camera:headingDirection16(heading)
    for i,name in ipairs(names16) do if direction==name then return i end end
end
function Test.run(check)
    local camera=Camera.new({x=100,z=100,heading=0},world)
    local outside16,outside8=true,true
    for _,yaw in ipairs({0,90,197,359}) do
        camera.yaw=yaw
        for _,tilt in ipairs({20,55,85}) do
            camera.tilt=tilt
            for i=1,16 do
                local heading=-math.pi/2+(i-1)*tau/16-math.rad(yaw)
                outside16=outside16 and cameraFrame16(camera,heading)==i
                if i%2==1 then outside8=outside8 and Art.frame(camera,heading,8)==(i+1)/2 end
            end
        end
    end
    check('commute_direction_all_sixteen_views_follow_outside_orbit_at_all_tilts',outside16)
    check('commute_direction_explicit_legacy_eight_view_api_preserves_authored_order',outside8)
    local boundaries=true;camera.yaw=0
    for i=1,16 do
        local edge=-math.pi/2+(i-.5)*tau/16
        boundaries=boundaries and cameraFrame16(camera,edge-1e-7)==i and cameraFrame16(camera,edge+1e-7)==i%16+1
    end
    check('commute_direction_outside_sector_boundaries_wrap_without_opposite_views',boundaries)
    camera.firstPerson=true;camera.eyeHeight=1.65;camera.viewPitch=0;camera.roll=0
    local fp16,fp8,projection=true,true,true
    for _,view in ipairs({0,.73,math.pi/2,tau-.001,tau+.001,-tau-.31}) do
        camera.viewHeading=view;camera.yaw=123
        for i=1,16 do
            local heading=view+(i-1)*tau/16
            fp16=fp16 and cameraFrame16(camera,heading)==i
            if i%2==1 then fp8=fp8 and Art.frame(camera,heading,8)==(i+1)/2 end
            local right,_,forward=FP.coordinates(camera,camera.centerX+math.cos(heading),
                camera.centerZ+math.sin(heading),camera.eyeHeight)
            projection=projection and cameraFrame16(camera,heading)==frameFromVector(right,forward,16)
        end
    end
    check('commute_direction_first_person_all_sixteen_views_use_view_heading',fp16)
    check('commute_direction_first_person_legacy_eight_view_api_agrees',fp8)
    check('commute_direction_first_person_matches_actual_projection_right_forward_basis',projection)
    camera.viewHeading=.73
    local forward=cameraFrame16(camera,.73);camera.yaw=300
    local yawIgnored=cameraFrame16(camera,.73)==forward
    camera.viewHeading=.73+math.pi/2;local lookRight=cameraFrame16(camera,.73)
    camera.viewHeading=.73-math.pi/2;local lookLeft=cameraFrame16(camera,.73)
    check('commute_direction_head_look_changes_view_and_exterior_yaw_is_ignored',forward==1 and yawIgnored
        and lookRight==13 and lookLeft==5)
    boundaries=true
    for _,view in ipairs({-.1,tau-.1}) do
        camera.viewHeading=view
        for i=1,16 do
            local edge=view+(i-.5)*tau/16
            boundaries=boundaries and cameraFrame16(camera,edge-1e-7)==i
                and cameraFrame16(camera,edge+1e-7)==i%16+1
        end
    end
    check('commute_direction_first_person_wrap_and_half_sector_boundaries_are_continuous',boundaries)
    -- Sixteen-view rendering must reach every authored angle. The explicit
    -- legacy eight-view helper remains distinct, never an implicit fallback.
    local precision=true
    for _,view in ipairs({.73,tau-.01,-.31}) do
        camera.viewHeading=view
        for n=0,63 do
            local heading=view+n*tau/64+.001
            local right,_,forward=FP.coordinates(camera,camera.centerX+math.cos(heading),
                camera.centerZ+math.sin(heading),camera.eyeHeight)
            local expected8=frameFromVector(right,forward,8)
            local expected16=frameFromVector(right,forward,16)
            precision=precision and Art.frame(camera,heading,8)==expected8
                and Art.frame(camera,heading,16)==expected16
        end
    end
    check('commute_direction_legacy_api_preserves_projection_with_64_view_runtime',precision and Art.DIRECTION_COUNT==64)

    camera.firstPerson=false;camera.yaw=0
    local rear=Art.bank({heading=-math.pi/2},camera,-.3)
    local front=Art.bank({heading=math.pi/2},camera,-.3)
    check('commute_direction_bank_right_turn_reverses_between_rear_and_front_views',rear>0 and front<0
        and math.abs(rear-.16)<1e-10 and math.abs(front+.16)<1e-10
        and Art.bank({heading=-math.pi/2},camera,.3)<0 and Art.bank({heading=math.pi/2},camera,.3)>0)
    check('commute_direction_side_views_have_no_false_screen_roll',math.abs(Art.bank({heading=0},camera,-.3))<1e-10
        and math.abs(Art.bank({heading=math.pi},camera,.3))<1e-10)
    local projectedBank=true
    for _,yaw in ipairs({0,73,180,311}) do
        camera.yaw=yaw
        for n=0,7 do
            local heading=n*tau/8+.1
            local x0=camera:screen(100,100,0)
            local x1=camera:screen(100+math.sin(heading),100-math.cos(heading),0)
            local bank=Art.bank({heading=heading},camera,.1)
            projectedBank=projectedBank and bank*(x1-x0)>0
        end
    end
    check('commute_direction_bank_follows_projected_rider_left_across_camera_orbits',projectedBank)
    camera.firstPerson=true;camera.viewHeading=.73
    check('commute_direction_first_person_bank_matches_rear_front_and_side_view',Art.bank({heading=.73},camera,-.3)>0
        and Art.bank({heading=.73+math.pi},camera,-.3)<0
        and math.abs(Art.bank({heading=.73+math.pi/2},camera,-.3))<1e-10
        and math.abs(Art.bank({heading=.73-math.pi/2},camera,.3))<1e-10)
    camera.viewHeading=1.2
    local walkIdle=true
    for i=1,8 do
        local actor={heading=camera.viewHeading+(i-1)*tau/8,speed=1,distance=.65}
        local walk,mirror=Normal.selection(actor,camera);actor.speed=0
        local idle,idleMirror=Normal.selection(actor,camera)
        local authored=({'north','northeast','east','southeast','south','southeast','east','northeast'})[i]
        local suffix=authored=='east' and '' or '_'..authored
        walkIdle=walkIdle and walk=='walk'..suffix and idle=='idle'..suffix and mirror==idleMirror
            and mirror==(i>5 and -1 or 1)
    end
    check('commute_direction_onfoot_walk_and_idle_share_camera_relative_mirror_contract',walkIdle)

    -- Follow's authored poses must sample exactly one opaque facing quad.
    local savedGraphics=love.graphics
    local material=require('src.commute.bike_paint_art');local savedMaterialDraw=material.draw
    local calls={};local graphics={}
    for k,v in pairs(savedGraphics) do graphics[k]=v end
    local alpha=1
    graphics.setColor=function(_,_,_,a)alpha=a or 1 end
    graphics.draw=function(image,quad,x,y,rotation,sx,sy)
        calls[#calls+1]={state=image,frame=quad,sx=sx,sy=sy,rotation=rotation,alpha=alpha}
    end
    love.graphics=graphics
    -- This fixture uses state/frame tokens, not textures. Native material
    -- pixel tests cover tire/paint shading separately from direction routing.
    material.draw=function(image,quad,_,x,y,rotation,sx,sy,ax,ay)
        graphics.draw(image,quad,x,y,rotation,sx,sy,ax,ay)
    end
    local okay,reason=xpcall(function()
        local art=setmetatable({resolve=function(_,state,frame)return state,frame end},Art)
        local durations=require('src.commute.riding_animation').durations
        local samples={
            {state='parked',parked=true},
            {state='upright'},
            {state='brakeMid',speed=8,brakingPose=.5},{state='brake',speed=8,brakingPose=1},
            {state='aeroMid',speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2},
            {state='aero',speed=Bike.BOOST_MAX_SPEED},
            {state='turnLeftMid',lean=.225},{state='turnLeft',lean=.3},
            {state='turnRightMid',lean=-.225},{state='turnRight',lean=-.3},
            {state='boostMid',ridingAction='boost',ridingActionTime=durations.boost*5/6},
            {state='boost',ridingAction='boost',ridingActionTime=durations.boost/2},
            {state='shiftMid',ridingAction='shift',ridingActionTime=durations.shift*5/6},
            {state='shift',ridingAction='shift',ridingActionTime=durations.shift/2},
            {state='impactMid',impactPulse=Bike.IMPACT_DURATION*5/6,impactStrength=1},
            {state='impact',impactPulse=Bike.IMPACT_DURATION/2,impactStrength=1},
            {state='boostMid',speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2,lean=-.21,
                ridingAction='boost',ridingActionTime=durations.boost*.9},
        }
        camera.firstPerson=false;camera.yaw=37;camera.outsideMode='follow'
        local consistent=true
        for _,sample in ipairs(samples) do
            for sampleAngle=0,63 do
                calls={}
                local actor={x=100,z=100,h=0,heading=-math.pi/2+sampleAngle*tau/64+.001-math.rad(camera.yaw)}
                local expected=frameFromVector(math.sin(sampleAngle*tau/64+.001),math.cos(sampleAngle*tau/64+.001),sample.parked and 16 or 64)
                art:draw(actor,camera,world,sample.parked,sample)
                local found=false
                for _,draw in ipairs(calls) do
                    found=found or draw.state==sample.state
                    consistent=consistent and draw.frame==expected and draw.sx>0 and draw.sy>0 and draw.alpha==1
                end
                consistent=consistent and found and #calls==1
            end
        end
        check('commute_direction_every_64_view_pose_and_parked_draw_one_opaque_unmirrored_view',consistent)
    end,debug.traceback)
    love.graphics=savedGraphics
    material.draw=savedMaterialDraw
    if not okay then error(reason,0) end

    local right,left=Bike.new(100,100,0),Bike.new(100,100,0)
    right.speed,left.speed=10,10;right.gear,left.gear=3,3
    for _=1,60 do
        Bike.update(right,{steer=1,throttle=.5},1/60,world)
        Bike.update(left,{steer=-1,throttle=.5},1/60,world)
    end
    local leftHeading=(left.heading+math.pi)%tau-math.pi
    check('commute_direction_physics_right_turn_has_negative_lean_and_left_turn_positive',right.heading>0 and right.heading<math.pi
        and right.lean<0 and leftHeading<0 and left.lean>0)
    local rider=Rider.new(100,100,tau-.02,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    rider.bike.speed=8;rider.bike.lean=-.25;rider.bike.steering=.7
    local trip={version=Trip.VERSION,mapVersion=require('src.commute.roads').VERSION,token=31,
        origin='warehouse',destination='garden',purpose='weekend',participants={owner={slot=1,arrived=false,rider=rider}}}
    local snapshot=Trip.snapshot(trip);local part=snapshot.participants.owner
    check('commute_direction_network_snapshot_preserves_heading_and_signed_turn_presentation',part.rider.bike.heading==rider.bike.heading
        and part.presentation.lean==-.25 and part.presentation.steer==.7)
    local visual=C.visualRider(part,{sceneId='commute',x=101,y=102})
    check('commute_direction_network_position_interpolation_does_not_replace_heading',visual.bike.x==101 and visual.bike.z==102
        and visual.bike.heading==rider.bike.heading and part.rider.bike.x==100 and part.rider.bike.z==100)
end
return Test
