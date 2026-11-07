local Path=require('src.commute.driving_path')
local Test={}

function Test.run(check)
    local points={{x=0,z=0,h=0},{x=3,z=0,h=3},{x=3,z=4,h=7},{x=0,z=4,h=10}}
    local sample=Path.sample(points,10,.7)
    local ahead,heading=Path.lookAhead(points,0,0,2,2)
    local projectedAhead,projectedHeading=Path.lookAhead(points,0,2,2,2,true)
    local remaining,waypointDistance=Path.remaining(points,2,1,0)
    local inferredSpeedLimits=Path.speedLimits(points)
    local limitedPoints={{x=0,z=0},{x=3,z=0},{x=3,z=4,speedLimit=3},
        {x=0,z=4,speedLimit=6}}
    local speedLimits=Path.speedLimits(limitedPoints)
    local inferredHasGuidance=Path.hasTurnGuidance(points)
    local authoredHasGuidance=Path.hasTurnGuidance(limitedPoints)
    check('driving_path_shares_cached_route_measurements',Path.length(points)==10
        and Path.indexAtDistance(points,6)==3
        and Path.station(points,3)==7 and Path.station(points,4)==10
        and sample and sample.pathIndex==3 and math.abs(sample.x-3)<1e-8
            and math.abs(sample.z-4)<1e-8 and math.abs(sample.h-7)<1e-8
        and ahead and math.abs(ahead.x-2)<1e-8 and math.abs(ahead.z)<1e-8
            and math.abs(heading)<1e-8
        and projectedAhead and math.abs(projectedAhead.x-2)<1e-8
            and math.abs(projectedAhead.z)<1e-8 and math.abs(projectedHeading)<1e-8
        and math.abs(remaining-9)<1e-8 and math.abs(waypointDistance-2)<1e-8)
    check('driving_path_caches_sparse_speed_limit_markers',#speedLimits==2
        and speedLimits==Path.speedLimits(limitedPoints)
        and speedLimits[1].index==3 and speedLimits[1].distanceBefore==3 and speedLimits[1].speed==3
        and speedLimits[2].index==4 and speedLimits[2].distanceBefore==7 and speedLimits[2].speed==6)
    check('driving_path_derives_turn_limits_for_unannotated_routes',#inferredSpeedLimits==2
        and inferredSpeedLimits[1].index==2 and inferredSpeedLimits[1].distanceBefore==0
        and inferredSpeedLimits[1].speed==2.7
        and inferredSpeedLimits[2].index==3 and inferredSpeedLimits[2].distanceBefore==3
        and inferredSpeedLimits[2].speed==2.7
        and not inferredHasGuidance and authoredHasGuidance,
        ('inferred=%s authored=%s'):format(tostring(inferredHasGuidance),tostring(authoredHasGuidance)))
end

return Test
