-- The dock is a reversing destination, not a road bend. The road controller
-- handles the approach; this controller owns only the slow, straight back-in.
local Truck=require('src.commute.delivery_truck')
local Watchdog=require('src.ai_watchdog')
local Dock={}
local plans=setmetatable({}, {__mode='k'})
local function wrap(angle)return math.atan2(math.sin(angle),math.cos(angle))end
local function clamp(value,lo,hi)return math.max(lo,math.min(hi,value))end

function Dock.clear(vehicle,state,reason)
    local plan=plans[vehicle]
    if plan then Watchdog.clear(state,plan.monitor,reason);plans[vehicle]=nil end
end

function Dock.plan(vehicle,points,world,state)
    local site=world.truckAccess and world.sites and world.sites.byId.warehouse
    local last=points and points[#points]
    if not site or not last or not site.truckParking
        or (last.x-site.truckParking.x)^2+(last.z-site.truckParking.z)^2>.01 then return nil end
    local plan=plans[vehicle]
    if plan and plan.source==points then return plan end
    Dock.clear(vehicle,state,'Dock approach replanned')
    local setup=require('src.commute.sites').warehouseTruckLayout.truckDockSetup
    local sx,sz=site:toWorld(setup.x,setup.z,0)
    local forward={}
    for _,point in ipairs(points) do
        forward[#forward+1]=point
        if (point.x-sx)^2+(point.z-sz)^2<.01 then break end
    end
    if #forward==#points then
        -- A restored truck may already be on the final straight reversing leg.
        forward={{x=vehicle.x,z=vehicle.z,h=vehicle.h},{x=sx,z=sz,h=site.h}}
    end
    local x,z=site:toLocal(vehicle.x,vehicle.z)
    local aligned=x>=site.design.truckParking.x-.25 and x<=setup.x+1
        and math.abs(z-site.design.truckParking.z)<.65
        and math.abs(wrap(vehicle.heading-site.yaw))<.18
    plan={source=points,forward=forward,site=site,stage=aligned and 'reverse' or 'approach',
        bestDistance=math.huge,monitor={}}
    plans[vehicle]=plan
    return plan
end

function Dock.reverse(vehicle,plan,dt,world,state)
    local site=plan.site
    local dock=site.truckParking
    local dx,dz=dock.x-vehicle.x,dock.z-vehicle.z
    local distance=math.sqrt(dx*dx+dz*dz)
    local headingError=wrap(site.yaw-vehicle.heading)
    local along=(vehicle.x-dock.x)*site.cos+(vehicle.z-dock.z)*site.sin
    local side=-(vehicle.x-dock.x)*site.sin+(vehicle.z-dock.z)*site.cos
    local finished=distance<.28 and math.abs(headingError)<.12
    -- Aim along the dock's centerline; damp heading corrections as the rear
    -- doors reach the threshold. Reverse steering has the opposite yaw sign.
    local aimHeading=site.yaw+math.atan2(side,math.max(2,along))
    local steer=clamp(-wrap(aimHeading-vehicle.heading)/.5,-.65,.65)
    local desired=math.min(1.5,math.sqrt(2*1.5*math.max(0,distance-.12)))
    local clearance=math.min(distance,.65+vehicle.speed*vehicle.speed/6)
    local obstructed=Truck.blocked(world,vehicle.x-math.cos(vehicle.heading)*clearance,
        vehicle.z-math.sin(vehicle.heading)*clearance,vehicle.heading,vehicle)
    local hold=finished or obstructed
    local brake=hold and 1 or (vehicle.speed>desired and clamp((vehicle.speed-desired)*2,0,1) or 0)
    world.activeTruck=vehicle
    local moved=Truck.update(vehicle,{drive=hold and 0 or 1,steer=steer,brake=brake},dt,world)
    world.activeTruck=nil
    if finished and vehicle.speed<.05 then
        -- Settle within parking tolerance only after a full footprint check.
        if not Truck.blocked(world,dock.x,dock.z,site.yaw,vehicle) then
            vehicle.x,vehicle.z,vehicle.heading=dock.x,dock.z,site.yaw
            vehicle.speed=0;vehicle.steering=0;vehicle.slipAngle=0
            Watchdog.clear(state,plan.monitor,'Truck backed into the loading dock')
            return true
        end
    end
    local progressed=distance<plan.bestDistance-.12
    if progressed then plan.bestDistance=distance end
    Watchdog.observe(state,plan.monitor,{issueId='delivery-dock:'..tostring(vehicle.trafficId or 'truck'),
        system='Delivery docking',subject=vehicle.trafficId or 'Delivery truck',stage='backing_to_dock',
        dt=dt,timeout=8,retryDelay=8,progressed=progressed,
        reason='Truck has not made progress backing into the loading dock',
        x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation',
        recover=function(attempt)
            -- A blocked dock is not permission to teleport through a truck or
            -- a pedestrian. Retry the approach only at a collision-free pose.
            local setup=require('src.commute.sites').warehouseTruckLayout.truckDockSetup
            local sx,sz=site:toWorld(setup.x,setup.z,0)
            local detail=('attempt=%d distance=%.2f lateral=%.2f headingError=%.3f moved=%.3f speed=%.2f blocked=%s')
                :format(attempt,distance,side,headingError,moved,vehicle.speed,tostring(obstructed))
            for _,entry in ipairs(world.trafficActors or {}) do
                local other=entry.actor or entry
                if other~=vehicle and other.x and other.z
                    and (other.x-vehicle.x)^2+(other.z-vehicle.z)^2<12^2 then
                    detail=detail..('\nNearby %s %s at %.2f,%.2f speed=%.2f')
                        :format(entry.kind or 'actor',entry.id or other.trafficId or 'unknown',
                            other.x,other.z,other.speed or 0)
                end
            end
            if attempt>=3 and not Truck.blocked(world,sx,sz,site.yaw,vehicle) then
                vehicle.x,vehicle.z,vehicle.heading=sx,sz,site.yaw
                vehicle.h=world:supportHeight(sx,sz)
                vehicle.speed=0;vehicle.steering=0;vehicle.slipAngle=0;vehicle.collisionContact=nil
                plan.bestDistance=math.huge
                return {ok=true,action='Reset to the clear dock approach and retried backing in',detail=detail}
            end
            return {ok=false,action='Dock approach obstructed; holding and checking for clearance',detail=detail}
        end})
    return false
end

return Dock
