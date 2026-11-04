-- Real application input/update/draw paths, including actual touch contacts.
local C=require('src.commute.runtime')
local Bike=require('src.commute.motorcycle')
local Bindings=require('src.commute.bindings')
local Camera=require('src.commute.camera')
local Copy=require('src.save_schema').copy
local Test={}
function Test.run(R,check,realDrive,capture)
    local part=C.localPart(R);local rider=part.rider;local bike=rider.bike
    local saved=Copy(bike);local presentation=part.presentation;local camera=R._commute.camera
    local oldDrive,oldKeys=Bindings.drive,love.keyboard.isDown
    local profile=C.bindings(R);local mode=profile.outsideCamera;local keys={}
    Bindings.drive=realDrive
    love.keyboard.isDown=function(...)
        for i=1,select('#',...) do if keys[select(i,...)] then return true end end
        return false
    end
    local okay,reason=xpcall(function()
        local segment
        for _,s in ipairs(C.world(R).roads.segments) do
            if not s.bridge and s.distance>40 and s.width>=6 then segment=s;break end
        end
        assert(segment)
        local heading=math.atan2(segment.b.z-segment.a.z,segment.b.x-segment.a.x)
        local function place()
            bike.x,bike.z=(segment.a.x+segment.b.x)*.5,(segment.a.z+segment.b.z)*.5
            bike.heading,bike.speed,bike.reverse,bike.gear=heading,0,false,1
            bike.shiftTime,bike.shiftCooldown,bike.damage,bike.lean,bike.steering=0,0,37,0,0
            bike.steeringVelocity,bike.leanVelocity=0,0
            Bike.resetContact(bike,C.world(R));Bike.resetHorizontal(bike)
            part.presentation=nil;C.syncPlayer(R.World.player,part)
            R._commute.camera=Camera.new(bike,C.world(R));profile.outsideCamera='follow'
            R._commute.camera:setOutsideMode('follow',bike)
        end
        local function ticks(n)for _=1,n do R.App.update(1/60)end end
        place();local x,z=bike.x,bike.z
        keys[profile.keyboard.brake]=true;ticks(45)
        check('auto_reverse_runtime_keyboard_brake_backs_up_without_direction_button',bike.reverse
            and (bike.x-x)*math.cos(heading)+(bike.z-z)*math.sin(heading)<-.1)
        keys={};keys[profile.keyboard.accelerate]=true;ticks(75)
        check('auto_reverse_runtime_keyboard_forward_stops_reverse_then_drives_ahead',not bike.reverse
            and bike.vx*math.cos(heading)+bike.vz*math.sin(heading)>0)
        keys={};place();x,z=bike.x,bike.z
        local point=profile.layout.stick
        local cx,cy=point.x*R.Config.baseWidth,point.y*R.Config.baseHeight
        local reach=math.min(R.Config.baseWidth,R.Config.baseHeight)*.09
        assert(C.touchPressed(R,'auto-reverse-stick',cx,cy))
        assert(C.touchMoved(R,'auto-reverse-stick',cx,cy+reach));ticks(45)
        check('auto_reverse_runtime_touch_stick_backs_up_without_direction_button',bike.reverse
            and (bike.x-x)*math.cos(heading)+(bike.z-z)*math.sin(heading)<-.1)
        assert(C.touchMoved(R,'auto-reverse-stick',cx,cy-reach));ticks(75)
        check('auto_reverse_runtime_touch_forward_stops_reverse_then_drives_ahead',not bike.reverse
            and bike.vx*math.cos(heading)+bike.vz*math.sin(heading)>0)
        C.touchReleased(R,'auto-reverse-stick')
        capture(R,'condition-readout-clear')
        if C.mobileInputEnabled(R) then
            place();local cam=R._commute.camera
            profile.outsideCamera='fixed';cam:setOutsideMode('fixed',bike)
            cam:orbit(-heading*180/math.pi-cam.yaw,0)
            assert(C.touchPressed(R,'free-stick',cx,cy))
            assert(C.touchMoved(R,'free-stick',cx+reach,cy))
            local aligned,power=C.localInput(R)
            assert(C.touchPressed(R,'free-orbit',R.Config.baseWidth*.5,R.Config.baseHeight*.4))
            assert(C.touchMoved(R,'free-orbit',R.Config.baseWidth*.5+160,R.Config.baseHeight*.4))
            local turn,afterOrbit=C.localInput(R)
            check('free_touch_runtime_second_finger_orbits_held_stick',math.abs(aligned)<.001 and power<-.99
                and math.abs(turn)>.2 and afterOrbit<0)
            assert(C.touchReleased(R,'free-orbit'))
            x,z=bike.x,bike.z;ticks(30)
            check('free_touch_runtime_moves_after_orbit_without_retouching',not bike.reverse
                and (bike.x-x)^2+(bike.z-z)^2>.01)
            capture(R,'free-camera-mobile-aim')
            C.touchReleased(R,'free-stick')
            local neutral,coast=C.localInput(R)
            check('free_touch_runtime_lift_returns_to_coast',neutral==0 and coast==0)
        end
    end,debug.traceback)
    C.touchReleased(R,'auto-reverse-stick')
    C.touchReleased(R,'free-orbit');C.touchReleased(R,'free-stick')
    Bindings.drive,love.keyboard.isDown=oldDrive,oldKeys
    for key in pairs(bike) do bike[key]=nil end
    for key,value in pairs(saved) do bike[key]=value end
    part.presentation=presentation;R._commute.camera=camera;profile.outsideCamera=mode
    C.syncPlayer(R.World.player,part)
    assert(okay,reason)
end
return Test
