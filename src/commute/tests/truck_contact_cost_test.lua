local Truck=require('src.commute.delivery_truck')
local Footprint=require('src.commute.truck_footprint')
local Traffic=require('src.commute.delivery_traffic')
local Test={}

local function fixture(model,reverse,heading)
    heading=heading or 0
    local otherModel=model=='box' and 'kei' or 'box'
    local truck=Truck.new(100,100,heading,'plain',model)
    local direction=reverse and -1 or 1
    local gap=Footprint.dimensions(model).halfLength+Footprint.dimensions(otherModel).halfLength+.01
    local other=Truck.new(100+math.cos(heading)*gap*direction,
        100+math.sin(heading)*gap*direction,heading,'plain',otherModel)
    truck.speed=2;truck.reverse=reverse==true;other.engine=false
    local state={home={commute={participants={}}}}
    state.home.commute[model=='box' and 'truck' or 'keiTruck']=truck
    state.home.commute[otherModel=='box' and 'truck' or 'keiTruck']=other
    local world={supportHeight=function()return 0,'road' end,
        roads={sample=function()return 0,{width=40}end,blocked=function()return false end}}
    Traffic.installVehicleObstacles(state,world)
    return truck,other,world
end

-- Useful on a real phone too: detached vehicles/world, no save or session edits.
function Test.workload(legacy,steps)
    local truck,other,world=fixture('kei',false)
    local blocked=Truck.blocked
    local calls,contacts=0,0
    Truck.blocked=function(...)
        calls=calls+1
        if legacy then local hit=blocked(...);return hit end
        return blocked(...)
    end
    local start=love.timer.getTime()
    local okay,err=xpcall(function()
        for _=1,steps or 90 do
            Truck.update(truck,{drive=-1},1/60,world)
            if truck.collisionContact then contacts=contacts+1 end
        end
    end,debug.traceback)
    Truck.blocked=blocked
    assert(okay,err)
    return {calls=calls,contacts=contacts,milliseconds=(love.timer.getTime()-start)*1000,
        x=truck.x,z=truck.z,speed=truck.speed,otherX=other.x}
end

local function oldOverlap(x,z,c,s,ax,az,bx,bz,radius,dims)
    local dx,dz=(bx-ax)*.5,(bz-az)*.5
    local mx,mz=ax+dx-x,az+dz-z
    local along,side=mx*c+mz*s,-mx*s+mz*c
    local du,dv=dx*c+dz*s,-dx*s+dz*c
    if du==0 and dv==0 then
        local u=math.max(0,math.abs(along)-dims.halfLength)
        local v=math.max(0,math.abs(side)-dims.halfWidth)
        return u*u+v*v<=radius*radius
    end
    return math.abs(along)<=dims.halfLength+math.abs(du)+radius
        and math.abs(side)<=dims.halfWidth+math.abs(dv)+radius
        and math.abs(along*dv-side*du)<=dims.halfLength*math.abs(dv)+dims.halfWidth*math.abs(du)
            +radius*math.sqrt(du*du+dv*dv)
end

function Test.run(check)
    local classifications,normals,count=true,true,0
    for _,model in ipairs({'box','kei'})do
        local dims=Footprint.dimensions(model)
        for angle=0,7 do
            local c,s=math.cos(angle*.39),math.sin(angle*.39)
            for x=-4,4 do for z=-3,3 do
                for _,shape in ipairs({{x,z,x,z,.55},{x,z,x+2,z+1,.1},{x,z,x,z+4,0}})do
                    local hit,nx,nz=Footprint.overlaps(0,0,c,s,
                        shape[1],shape[2],shape[3],shape[4],shape[5],dims)
                    classifications=classifications and hit==oldOverlap(0,0,c,s,
                        shape[1],shape[2],shape[3],shape[4],shape[5],dims)
                    if hit then normals=normals and math.abs(nx*nx+nz*nz-1)<1e-10 end
                    count=count+1
                end
            end end
        end
    end
    check('truck_contact_normals_keep_existing_static_footprints',classifications,'classifications='..count)
    check('truck_contact_static_normals_are_finite_unit_vectors',normals)
    for _,model in ipairs({'box','kei'})do
        for _,reverse in ipairs({false,true})do
            for _,heading in ipairs({0,.37,1.2})do
                local truck,other,world=fixture(model,reverse,heading)
                local suffix=model..'_'..tostring(reverse)..'_'..heading
                local originX,originZ=truck.x,truck.z
                local counts,contacts=0,0
                local blocked=Truck.blocked
                Truck.blocked=function(...)counts=counts+1;return blocked(...)end
                local okay,err=xpcall(function()
                    for _=1,90 do
                        Truck.update(truck,{drive=reverse and 1 or -1},1/60,world)
                        if truck.collisionContact then contacts=contacts+1 end
                    end
                end,debug.traceback)
                Truck.blocked=blocked;assert(okay,err)
                check('truck_repeated_contact_cost_is_bounded_'..suffix,contacts>80 and counts<=95,
                    'contacts='..contacts..' blocked calls='..counts)
                check('truck_head_on_contact_stays_outside_other_vehicle_'..suffix,truck.speed==0
                    and not Footprint.overlapsTruck(truck.x,truck.z,truck.heading,
                        other.x,other.z,other.heading,truck.model,other.model))
                local stoppedX,stoppedZ=truck.x,truck.z
                for _=1,30 do Truck.update(truck,{},1/60,world)end
                check('truck_neutral_contact_does_not_creep_'..suffix,truck.x==stoppedX and truck.z==stoppedZ)
                for _=1,120 do Truck.update(truck,{drive=reverse and -1 or 1},1/60,world)end
                check('truck_can_back_away_from_contact_'..suffix,not truck.collisionContact
                    and (truck.x-originX)^2+(truck.z-originZ)^2>.5 and truck.speed>0)
            end
        end
    end
    local legacy,candidate=Test.workload(true),Test.workload(false)
    check('truck_contact_avoids_world_search_amplification',legacy.calls>candidate.calls*40
        and candidate.contacts==legacy.contacts and candidate.x==legacy.x and candidate.z==legacy.z,
        ('legacy=%d / %.3fms candidate=%d / %.3fms'):format(
            legacy.calls,legacy.milliseconds,candidate.calls,candidate.milliseconds))
    for _,kind in ipairs({'infrastructure','site'})do
        local truck,_,world=fixture('kei',false)
        world.vehicleObstacles=nil
        local wallX=101.77
        if kind=='infrastructure' then
            local shape={kind='guardrail',ax=wallX,az=95,bx=wallX,bz=105,radius=0,roadId='other'}
            world.infrastructure=setmetatable({bins={['8:8']={shape}}},require('src.commute.infrastructure'))
        else
            local corners={{x=wallX,z=95},{x=wallX+.2,z=95},{x=wallX+.2,z=105},{x=wallX,z=105}}
            local site={obstacles={},footprints={{minX=wallX,maxX=wallX+.2,minZ=95,maxZ=105,corners=corners}}}
            world.sites={nearby=function()return {site}end}
        end
        local calls,blocked=0,Truck.blocked
        Truck.blocked=function(...)calls=calls+1;return blocked(...)end
        local okay,err=xpcall(function()
            for _=1,90 do Truck.update(truck,{drive=-1},1/60,world)end
        end,debug.traceback)
        Truck.blocked=blocked;assert(okay,err)
        check('truck_'..kind..'_contact_passes_exact_normal_without_world_search',
            truck.collisionContact and truck.speed==0 and truck.x+Footprint.dimensions(truck).halfLength<wallX
                and calls<=95,'blocked calls='..calls)
    end
    local truck,_,world=fixture('kei',false)
    local staticHit=Footprint.overlapsTruck(truck.x,truck.z,truck.heading,truck.x+10,truck.z,0,'kei','box')
    check('truck_separated_footprints_still_clear',not staticHit)
    -- Contact-normal support is optional for custom worlds and travel limits.
    world.vehicleObstacles=function(x)return x>100.01 end
    Truck.update(truck,{drive=-1},1/60,world)
    check('truck_unknown_collision_keeps_safe_legacy_fallback',truck.speed==0 and truck.x<=100.01)
end
return Test
