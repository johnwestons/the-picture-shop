-- A disabled engine is a service problem, never a pathfinding problem.
local Power={}
local reported=setmetatable({},{__mode='k'})
function Power.reason(vehicle)
    if vehicle.service and vehicle.service.mechanicalFailure then return 'mechanical_failure','Truck needs engine repairs.' end
    if (vehicle.fuel or 1)<=0 then return 'fuel_empty','Truck needs fuel.' end
    if vehicle.engine==false then return 'engine_off','Truck engine is switched off.' end
end
function Power.report(state,vehicle,id,stage)
    local reason,message=Power.reason(vehicle)
    if not reason then reported[vehicle]=nil;return false end
    require('src.commute.yard_rail').stop(vehicle)
    local previous=reported[vehicle]
    if previous and previous.state==state and previous.id==id and previous.reason==reason then return true end
    reported[vehicle]={state=state,id=id,reason=reason}
    require('src.ai_watchdog').note(state,id,{status='STALLED',system='Truck service',
        subject=vehicle.trafficId or 'Company truck',stage=stage,reason=message,
        action='Use the truck service button below to refuel, repair, or restart in place.',detail=reason,
        x=vehicle.x,z=vehicle.z,visible=vehicle.visible~=false,scope='world-simulation'})
    return true
end
return Power
