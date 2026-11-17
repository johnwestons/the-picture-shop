-- ETA is presentation data once a physical truck owns the receiving dock.
-- Legacy journeys with no physical vehicle may still finish by their old ETA.
local Departure={}
function Departure.pending(delivery,epoch)
    local outbound=delivery and delivery.returnRoute
    if not outbound or type(outbound.departedAtEpoch)~='number' or epoch<outbound.departedAtEpoch then return false end
    if outbound.vehicle then return outbound.vehicle.phase~='offmap' end
    local inbound=delivery.route and delivery.route.vehicle
    if inbound and inbound.phase=='at_bay' then return true end
    return type(outbound.arrivedAtEpoch)~='number' or epoch<outbound.arrivedAtEpoch
end
return Departure
