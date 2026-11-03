-- Trace the generated shortcuts on the same road graph and surfaces the bike uses.
local Town=require('src.commute.town')
local Routes=require('src.commute.routes')
local Roads=require('src.commute.roads')
local Bike=require('src.commute.motorcycle')
local Test={}
local function at(p)return {x=p[1],z=p[2],h=p[3]} end
function Test.run(check)
    local allConnected,allShorter,allClear,allRecreation,physics=true,true,true,true,true
    local kinds={}
    for _,seed in ipairs({2,42,712345}) do
        local town=assert(Town.generate(seed));local world=Town.world(town)
        local paved,trails,heads={},{},{}
        for _,r in ipairs(town.roads) do
            if r.role=='trail' then
                trails[#trails+1]=r
                heads[r.id..'-in'],heads[r.id..'-out']=at(r.points[1]),at(r.points[#r.points])
            else paved[#paved+1]=r end
        end
        local streets=Roads.new({definitions=paved,destinations=heads,sites=world.sites})
        local pavedGraph=Routes.new(streets)
        allConnected=allConnected and #trails>=2 and #trails<=4
        for _,trail in ipairs(trails) do
            local detour=pavedGraph:find(trail.id..'-in',trail.id..'-out')
            local length=0
            for i=1,#trail.points-1 do
                local a,b=trail.points[i],trail.points[i+1]
                local dx,dz=b[1]-a[1],b[2]-a[2]
                local d=math.sqrt(dx*dx+dz*dz);length=length+d
                local x,z=(a[1]+b[1])*.5,(a[2]+b[2])*.5
                local ground=world:supportHeight(x,z)
                allClear=allClear and math.abs(b[3]-a[3])/d<=.281 and not world.roads:vegetationAllowed(x,z)
                    and not world:sweepObstacles(a[1],a[2],b[1],b[2],Bike.RADIUS,ground-.25,ground+1.2)
                for _,side in ipairs({-1,0,1}) do
                    local px,pz=x-side*dz/d*(trail.width*.5-.3),z+side*dx/d*(trail.width*.5-.3)
                    allClear=allClear and world.plan:height(px,pz)>.25 and not world.roads:blocked(world,px,pz)
                end
            end
            allConnected=allConnected and detour~=nil
            allShorter=allShorter and detour and length<detour.length*.89
            local p=trail.points[math.floor(#trail.points/2)]
            local bike=Bike.new(p[1],p[2],0)
            Bike.update(bike,{throttle=.2},1/60,world)
            local _,kind=world:supportHeight(p[1],p[2])
            physics=physics and bike.surface=='dirt' and kind=='trail'
            local start=trail.points[1]
            bike=Bike.new(start[1],start[2],0);Bike.update(bike,{},1/60,world)
            physics=physics and bike.surface=='road'
        end
        allRecreation=allRecreation and #town.recreation>=2 and #town.recreation<=3
        for _,area in ipairs(town.recreation) do
            local d=math.huge
            for _,s in ipairs(world.roads.segments) do if s.id==area.trailId then
                local t=math.max(0,math.min(1,((area.x-s.a.x)*s.dx+(area.z-s.a.z)*s.dz)/s.length2))
                d=math.min(d,math.sqrt((area.x-s.a.x-t*s.dx)^2+(area.z-s.a.z-t*s.dz)^2))
            end end
            kinds[area.kind]=true
            allRecreation=allRecreation and d<area.radius+3 and d>area.radius+.2
                and math.abs(world:height(area.x,area.z)-area.h)<.001
                and not world.roads:vegetationAllowed(area.x,area.z)
            for i=1,8 do
                local a=i*math.pi/4
                allRecreation=allRecreation and world.plan:height(area.x+area.radius*math.cos(a),
                    area.z+area.radius*math.sin(a))>.25
            end
        end
    end
    check('town_trails_connect_both_ends_to_paved_network',allConnected)
    check('town_trails_save_distance_over_a_real_paved_detour',allShorter)
    check('town_trails_width_is_dry_passable_and_clear_of_solid_scenery',allClear)
    check('town_trails_preserve_dirt_grip_and_paved_trailhead_grip',physics)
    check('town_trails_have_graded_dry_recreation_clearings_beside_paths',
        allRecreation and kinds.park and kinds.camp and kinds.picnic)
end
return Test
