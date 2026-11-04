local Art=require('src.commute.bike_art')
local Camera=require('src.commute.camera')
local Bike=require('src.commute.motorcycle')
local Test={}
local tau=math.pi*2
function Test.run(check)
    local world={height=function()return 0 end,supportHeight=function()return 0 end}
    local actor={x=100,z=100,h=0,heading=0,speed=6,lean=0}
    local camera=Camera.new(actor,world);local art=Art.new()
    local draw,setColor,newImage=love.graphics.draw,love.graphics.setColor,love.graphics.newImage
    local calls,alpha={},1
    love.graphics.setColor=function(_,_,_,a)alpha=a or 1 end
    love.graphics.draw=function(image,quad,_,_,_,sx,sy)
        local info=assert(art:describe(image,quad));info.alpha=alpha;info.sx=sx;info.sy=sy;calls[#calls+1]=info
    end
    local function drawn(state,frame,visual)
        calls={};art:draw(actor,camera,world,false,visual);local c=calls[1]
        return #calls==1 and c.state==state and c.frame==frame and c.alpha==1 and c.sx>0 and c.sy>0
    end
    local okay,reason=xpcall(function()
        local opaque=true
        for _,yaw in ipairs({0,37,90,193,359.99}) do
            camera.yaw=yaw
            for i=1,64 do
                actor.heading=-math.pi/2+(i-1)*tau/64-math.rad(yaw)
                for _,lean in ipairs({-.32,-.1,0,.1,.32}) do
                    actor.lean=lean
                    local state=math.abs(lean)<.15 and 'upright' or (lean>0 and 'turnLeft' or 'turnRight')
                    opaque=drawn(state,i) and opaque
                end
            end
        end
        check('bike_views_fixed_camera_reaches_all_64_opaque_upright_and_lean_views_across_orbits',opaque)
        camera.yaw=0
        local finer,boundaries=true,true
        for i=1,32 do
            local heading=-math.pi/2+(i-1)*tau/32+math.rad(3)
            finer=finer and Art.frame(camera,heading,64)==i*2 and Art.frame(camera,heading,32)==i
        end
        for i=1,64 do
            local edge=-math.pi/2+(i-.5)*tau/64
            boundaries=boundaries and Art.frame(camera,edge-1e-7,64)==i and Art.frame(camera,edge+1e-7,64)==i%64+1
        end
        check('bike_views_three_degree_heading_changes_reveal_new_intermediate_views',finer)
        check('bike_views_dense_sectors_wrap_at_exact_half_step_boundaries',boundaries)
        local d=require('src.commute.riding_animation').durations
        local samples={
            {'upright',{speed=0}},
            {'aeroMid',{speed=(Bike.TUCK_START_SPEED+Bike.BOOST_MAX_SPEED)/2}},
            {'aero',{speed=Bike.BOOST_MAX_SPEED}},
            {'turnLeftMid',{lean=.225}},{'turnLeft',{lean=.3}},
            {'turnRightMid',{lean=-.225}},{'turnRight',{lean=-.3}},
            {'brakeMid',{speed=8,brakingPose=.5}},{'brake',{speed=8,brakingPose=1}},
            {'boostMid',{ridingAction='boost',ridingActionTime=d.boost*5/6}},
            {'boost',{ridingAction='boost',ridingActionTime=d.boost/2}},
            {'shiftMid',{ridingAction='shift',ridingActionTime=d.shift*5/6}},
            {'shift',{ridingAction='shift',ridingActionTime=d.shift/2}},
            {'impactMid',{impactPulse=Bike.IMPACT_DURATION*5/6,impactStrength=1}},
            {'impact',{impactPulse=Bike.IMPACT_DURATION/2,impactStrength=1}},
        }
        actor.speed=0;actor.lean=0
        for _,mode in ipairs({'fixed','follow','perspective'}) do
            camera:setFirstPerson(mode=='perspective',actor)
            camera.outsideMode=mode;camera.viewHeading=.73;camera.yaw=37
            local complete=true
            for _,sample in ipairs(samples) do for i=1,64 do
                actor.heading=camera.firstPerson and camera.viewHeading+(i-1)*tau/64
                    or -math.pi/2+(i-1)*tau/64-math.rad(camera.yaw)
                complete=drawn(sample[1],i,sample[2]) and complete
            end end
            check('bike_views_'..mode..'_all_15_poses_reach_64_views_without_fading_or_mirroring',complete)
        end
        camera.firstPerson=false;camera.outsideMode='fixed';camera.yaw=0
        local single=true
        for n=0,100 do
            actor.heading=n*tau/101
            calls={};art:draw(actor,camera,world,false,{speed=n/100*16,lean=math.sin(n)*.3,
                ridingAction='boost',ridingActionTime=n/100*.78})
            single=single and #calls==1 and calls[1].alpha==1
        end
        check('bike_views_heading_and_pose_changes_never_overlay_transparent_bikes',single)
        actor.paintId='red';local painted=true
        for _,sample in ipairs(samples) do for i=1,64 do
            actor.heading=-math.pi/2+(i-1)*tau/64
            painted=drawn(sample[1],i,sample[2]) and painted
        end end
        check('bike_views_paint_shader_accepts_all_960_mounted_pose_direction_pairs',painted)
        -- Four riders can face different page quarters while all leaning at
        -- tuck speed. Their visible lean pairs fit in eight pages. Prewarming
        -- hidden tucks as well would exceed the cache and reupload every lap.
        art.actionPages:release();art.actionPages=require('src.commute.bike_action_pages').new()
        local uploads=0
        love.graphics.newImage=function(path,...)
            if type(path)=='string' and path:find('assets/commute/bike/actions-64/',1,true) then uploads=uploads+1 end
            return newImage(path,...)
        end
        local riders={}
        for i=1,4 do riders[i]={x=100+i*3,z=100,h=0,pitch=0,
            heading=-math.pi/2+(i-1)*math.pi/2,speed=Bike.BOOST_MAX_SPEED,lean=i%2==0 and -.3 or .3,
            ridingAnimation={kind='idle',remaining=0,queue={},accelerationWeight=0,brakingWeight=0}} end
        local function crowdFrame()
            calls={};for _,rider in ipairs(riders) do art:draw(rider,camera,world,false) end
        end
        crowdFrame();local initialUploads=uploads
        check('bike_views_four_high_speed_leaning_riders_warm_only_eight_visible_family_pages',
            initialUploads==8 and art.actionPages.count==8 and art.actionPages.peakCount==8)
        for _=1,120 do crowdFrame() end
        check('bike_views_four_rider_steady_rendering_stops_image_uploads_after_first_pass',
            uploads==initialUploads and art.actionPages.count==8 and art.actionPages.peakCount==8)
    end,debug.traceback)
    love.graphics.draw,love.graphics.setColor,love.graphics.newImage=draw,setColor,newImage
    art:release();assert(okay,reason)
end
return Test
