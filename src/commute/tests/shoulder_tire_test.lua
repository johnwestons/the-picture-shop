-- Compare the perspective rider on a real road against the identical frame
-- with the rider's depth test bypassed. Only the test reference bypasses depth.
local Bike=require('src.commute.motorcycle')
local Camera=require('src.commute.camera')
local FP=require('src.commute.first_person_camera')
local Test={}

local function changedPixels(a,b)
    if a==b then return 0 end
    local n=0
    for i=1,#a,4 do if a:byte(i)~=b:byte(i) or a:byte(i+1)~=b:byte(i+1) or a:byte(i+2)~=b:byte(i+2) then n=n+1 end end
    return n
end

function Test.run(renderer,segment,check)
    local g=love.graphics
    local world=renderer.world
    local bike=Bike.new((segment.a.x+segment.b.x)*.5,(segment.a.z+segment.b.z)*.5,
        math.atan2(segment.b.z-segment.a.z,segment.b.x-segment.a.x))
    Bike.resetContact(bike,world)
    local rider={bike=bike,gear={mounted=true}}
    local camera=Camera.new(bike,world)
    camera:setOutsideMode('shoulder',bike,true)
    local view=renderer:prewarmViews()
    local actors={{actor=bike,localPlayer=true}}
    local bypass,wall=false,false
    local scene=setmetatable({grassFields=false,tireTracks=false,bikeParticles=false,visibleProps={}}, {__index=renderer})
    scene.bikeArt={draw=function(_, ...)
        local mode,write=g.getDepthMode()
        if bypass then g.setDepthMode('always',false) end
        local y=renderer.bikeArt:draw(...)
        g.setDepthMode(mode,write)
        return y
    end}
    scene.structures={drawFirstPerson=function(_,eye)
        if not wall then return end
        -- A foreground occluder still has to hide the back tire.
        local x,y=eye:screen(bike.x,bike.z,bike.h)
        view.spriteShader:send('spriteDepth',FP.depthValue(1))
        view.spriteShader:send('spriteFog',0)
        g.setShader(view.spriteShader);g.setColor(.17,.25,.43)
        g.rectangle('fill',x-48,y-80,96,100)
    end}
    local function frame(entries,noDepth)
        bypass=noDepth
        view:draw(scene,camera.shoulderView,bike,entries)
        local pixels=view.canvas:newImageData()
        local bytes=pixels:getString();pixels:release()
        return bytes
    end
    for _,case in ipairs({{6,0,0},{14,0,0},{14,35,.25},{35,-55,-.25}}) do
        local tilt,orbit,lean=unpack(case)
        bike.lean=lean;camera:recenter();camera:orbit(orbit,tilt-camera.tilt)
        camera:updateRide(rider,0)
        local empty=frame({},false)
        local reference=frame(actors,true)
        local actual=frame(actors,false)
        local missing=changedPixels(actual,reference)
        check(('shoulder_tire_clears_real_road_at_%d_tilt_%d_orbit'):format(tilt,orbit),
            changedPixels(empty,reference)>1000 and missing==0,'clipped rider pixels='..missing)
        if tilt==6 then
            local eye=camera.shoulderView
            local _,anchor=eye:screen(bike.x,bike.z,bike.h)
            check('shoulder_steering_marker_tracks_adjusted_sprite_pivot',eye.riderSpriteScale and eye.riderSpriteY<anchor)
        end
    end
    local parking=world.roads.destinations.warehouse
    bike.x,bike.z,bike.lean=parking.x,parking.z,0
    Bike.resetContact(bike,world)
    bike.h=bike.h-.12 -- loaded suspension can sit below the drawn parking surface
    camera:recenter();camera:updateRide(rider,0)
    local missing=changedPixels(frame(actors,false),frame(actors,true))
    check('shoulder_tire_clears_parking_surface_with_compressed_suspension',missing==0,'clipped rider pixels='..missing)
    wall=true
    check('shoulder_foreground_geometry_still_occludes_rider',changedPixels(frame(actors,false),frame(actors,true))>100)
end
return Test
