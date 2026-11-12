local Tracks=require("src.commute.foot_tracks")

local Test={}

local function sample(support)
    local tracks=Tracks.new()
    local world={supportHeight=function() return .5,support end}
    local actor={x=0,z=0}
    tracks:update("walker",actor,world,true,0)
    actor.x=2
    tracks:update("walker",actor,world,true,1)
    return tracks
end

function Test.run(check)
    local trail=sample("trail")
    local trailMarks=trail.players.walker and trail.players.walker.marks or {}
    check("commute_foot_tracks_leave_steps_on_trails",
        #trailMarks>=2 and trailMarks[1].material=="dirt")

    local road=sample("road")
    check("commute_foot_tracks_leave_no_steps_on_roads",
        #((road.players.walker and road.players.walker.marks) or {})==0)

    local bridge=sample("bridge")
    check("commute_foot_tracks_leave_no_steps_on_bridges",
        #((bridge.players.walker and bridge.players.walker.marks) or {})==0)

    local sidewalk=sample("sidewalk")
    local sidewalkMarks=sidewalk.players.walker and sidewalk.players.walker.marks or {}
    check("commute_foot_tracks_leave_faint_sidewalk_steps",
        #sidewalkMarks>=2 and sidewalkMarks[1].material=="sidewalk")

    local relocation=Tracks.new()
    local world={supportHeight=function() return .5,"trail" end}
    local actor={x=0,z=0}
    relocation:update("walker",actor,world,true,0)
    actor.x=8
    relocation:update("walker",actor,world,true,1)
    check("commute_foot_tracks_ignore_position_snaps",
        #((relocation.players.walker and relocation.players.walker.marks) or {})==0)

    trail:update("walker",actor,world,true,20)
    check("commute_foot_tracks_expire_old_steps",
        #((trail.players.walker and trail.players.walker.marks) or {})==0)
end

return Test
