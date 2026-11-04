local Tire=require('src.commute.bike_tire_motion')
local Regions=require('assets.commute.bike.wheel_regions')
local Test={}
function Test.run(check)
    local coverage,stopped,moving=true,true,true;local count=0
    local actor={speed=8,distance=17.4}
    for pose,rows in pairs(Regions) do
        coverage=coverage and #rows==64
        for frame,row in ipairs(rows) do
            count=count+1
            local sample=Tire.sample(actor,nil,pose,frame)
            coverage=coverage and #row==8 and sample~=nil
            for wheel=0,1 do
                local n=wheel*4
                coverage=coverage and (wheel==1 and row[n+3]==0 or
                    row[n+1]>25 and row[n+1]<295 and row[n+2]>185 and row[n+2]<280
                    and row[n+3]>=8 and row[n+3]<=37 and row[n+4]>=23 and row[n+4]<=33)
            end
            moving=moving and sample.motion[2]>0 and sample.motion[2]<=1
            stopped=stopped and Tire.sample(actor,{speed=0,distance=99},pose,frame)==nil
        end
    end
    check('bike_tires_all_960_mounted_pose_views_have_bounded_lower_wheel_regions',coverage and count==960)
    check('bike_tires_every_mounted_pose_activates_only_with_actual_movement',moving and stopped)
    check('bike_tires_parked_bike_never_animates_even_with_stale_speed',Tire.sample(actor,nil,'parked',1)==nil)
    local one=Tire.sample(actor,nil,'upright',17)
    local again=Tire.sample(actor,nil,'upright',17)
    actor.distance=actor.distance+.23;local moved=Tire.sample(actor,nil,'upright',17)
    check('bike_tires_phase_uses_distance_and_repeated_draws_do_not_advance_it',one.motion[1]==again.motion[1] and moved.motion[1]~=one.motion[1])
    actor.reverse=true;local reversed=Tire.sample(actor,nil,'upright',17)
    check('bike_tires_reverse_uses_opposite_distance_phase',reversed.motion[1]==-moved.motion[1])
    local visual=Tire.sample(actor,{speed=2,distance=.5,reverse=false},'brake',64)
    actor.reverse=false;actor.speed=2;actor.distance=.5
    local localSample=Tire.sample(actor,nil,'brake',64)
    check('bike_tires_remote_presentation_and_local_distance_select_identical_motion',visual.motion[1]==localSample.motion[1]
        and visual.motion[2]==localSample.motion[2] and visual.wheel1[1]==localSample.wheel1[1])
    local Art=require('src.commute.bike_paint_art');local uniforms={}
    local target={send=function(_,key,value)uniforms[key]=value end}
    local image={getDimensions=function()return 1280,1280 end}
    local quad={getViewport=function()return 0,0,320,320 end}
    Art.configure(target,'bronze',image,quad,1,'upright',nil,actor)
    local movingUniform=uniforms.bikeTireEnabled==true and uniforms.bikePaintEnabled==false
    Art.configure(target,'bronze',image,nil,1,'parked','firstPerson',actor)
    check('bike_tires_shared_cockpit_shader_clears_previous_moving_bike_uniforms',movingUniform and uniforms.bikeTireEnabled==false)
    Art.configure(target,'red',image,quad,1,'parked',nil,actor)
    check('bike_tires_parked_repainting_keeps_paint_but_disables_tire_motion',uniforms.bikePaintEnabled==true and uniforms.bikeTireEnabled==false)
end
return Test
