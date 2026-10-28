local Technician = require("src.technician")
local Config = require("src.config")
local Test = {}

local function visit(route)
    return {technicianVisit={kind="cutter",species="mouse",status="entering",visible=true,
        x=route[1].x,y=route[1].y,route=route,waypoint=2,animationClock=0,serviceTimer=0}}
end

local function navigation(obstacles)
    local mask = {}
    function mask:getDimensions() return Config.baseWidth,Config.baseHeight end
    function mask:getPixel() return 1,1,1,1 end
    return {assets={getData=function() return mask end},obstacles=function() return obstacles end}
end

function Test.run(context,check)
    for _,species in ipairs({"mouse","lizard"}) do
        local valid=true
        for _,v in ipairs({{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}}) do
            local stopped={species=species,status="entering",inMotion=false,intentX=v[1],intentY=v[2],idleClock=0}
            local character,action,frame=Technician.spritePose(stopped,context.characterAssets)
            local image,quad,count=context.characterAssets.get(character,action,frame)
            local ax,ay=context.characterAssets.getAnchor(character,action,frame)
            stopped.idleClock=2/.65-.07
            local _,blinkAction,blinkFrame=Technician.spritePose(stopped,context.characterAssets)
            local bx,by=context.characterAssets.getAnchor(character,blinkAction,blinkFrame)
            valid=valid and character==Config.technician.characters[species] and image and quad and count==2
                and frame==1 and blinkFrame==2 and action==blinkAction and ay==229 and by==229 and math.abs(ax-bx)<=1
        end
        check("technician_"..species.."_has_eight_authored_planted_idle_views",valid)
    end
    for _,species in ipairs({"mouse","lizard"}) do
      for _,view in ipairs({{name="north",x=0,y=-1,action="walk_north"},
          {name="south",x=0,y=1,action="walk_south"},{name="east",x=1,y=0,action="walk"}}) do
      local authoredWalk=true
      for phase=1,8 do
        local walking={species=species,status="exiting",inMotion=true,intentX=view.x,intentY=view.y,
            animationDistance=(phase-1)*Config.technician.walkPixelsPerFrame+.5}
        local character,action,frame=Technician.spritePose(walking,context.characterAssets)
        local image,quad,count=context.characterAssets.get(character,action,frame)
        local _,ay=context.characterAssets.getAnchor(character,action,frame)
        authoredWalk=authoredWalk and image and quad and action==view.action and frame==phase and count==8 and ay==229
      end
      check("technician_"..species.."_"..view.name.."_walk_uses_eight_authored_distance_phases",authoredWalk)
      end
    end
    local corner=visit({{x=0,y=0},{x=3,y=0},{x=3,y=-20}})
    Technician.update(.1,corner,false,.1)
    local a=corner.technicianVisit
    local net=math.sqrt(a.x*a.x+a.y*a.y)
    check("technician_stride_counts_all_corner_segments",a.animationDistance>net+.1
        and a.intentX==0 and a.intentY==-1 and a.inMotion and a.idleClock==0)

    local clockPose={status="entering",inMotion=true,animationDistance=7,animationClock=0}
    local x,y,r=Technician.pose(clockPose)
    clockPose.animationClock=100
    local x2,y2,r2=Technician.pose(clockPose)
    check("technician_walk_phase_depends_on_travel_not_elapsed_clock",x==x2 and y==y2 and r==r2)
    clockPose.inMotion=false
    x,y,r=Technician.pose(clockPose)
    check("technician_blocked_pose_stays_planted",x==0 and y==0 and r==0)

    -- The navigation world includes connected rooms beyond the warehouse
    -- canvas. Span those too, so this fixture has no legitimate detour.
    local wall={{x=400,y=350,halfWidth=12,halfHeight=10000}}
    local context=navigation(wall)
    local blocked=visit({{x=200,y=350},{x=700,y=350}})
    blocked.technicianVisit.inMotion=true
    for _=1,8 do Technician.update(.1,blocked,false,.1,context) end
    local b=blocked.technicianVisit
    check("technician_blocked_navigation_freezes_distance_and_clears_stale_motion",
        b.x==200 and b.y==350 and b.animationDistance==0 and not b.inMotion and b.idleClock>.7,
        string.format("x=%.3f y=%.3f distance=%.3f idle=%.3f moving=%s",b.x,b.y,b.animationDistance,b.idleClock,tostring(b.inMotion)))
    wall[1]=nil
    for _=1,8 do Technician.update(.1,blocked,false,.1,context) end
    check("technician_resumes_from_a_reopened_route",b.x>200 and b.animationDistance>0 and b.inMotion and b.idleClock==0)

    local slow=visit({{x=100,y=350},{x=900,y=350}})
    local fast=visit({{x=100,y=350},{x=900,y=350}})
    slow.technicianVisit.animationDistance,fast.technicianVisit.animationDistance=13,39
    Technician.update(1,slow,false,1)
    Technician.update(1,fast,false,1)
    check("technician_speed_and_visible_phase_share_the_gait_curve",
        fast.technicianVisit.x>slow.technicianVisit.x
        and slow.technicianVisit.gaitSpeedMultiplier<1 and fast.technicianVisit.gaitSpeedMultiplier>1)

    local legacy=visit({{x=200,y=350},{x=700,y=350}})
    legacy.technicianVisit.directionFrame=2
    local migrated=Technician.ensure(legacy)
    check("technician_legacy_visits_receive_motion_defaults",migrated.animationDistance==0
        and migrated.idleClock==0 and migrated.intentX==0 and migrated.intentY==-1)
    local paused=visit({{x=200,y=350},{x=700,y=350}})
    Technician.update(10,paused,false,0)
    check("technician_zero_motion_time_cannot_advance_stride",paused.technicianVisit.animationDistance==0
        and paused.technicianVisit.x==200 and not paused.technicianVisit.inMotion)
end

return Test
