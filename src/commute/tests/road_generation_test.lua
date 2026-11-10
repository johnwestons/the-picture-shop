local Town=require('src.commute.town')
local Roads=require('src.commute.roads')
local Routes=require('src.commute.routes')
local Rules=require('src.commute.traffic_rules')
local Truck=require('src.commute.delivery_truck')
local Footprint=require('src.commute.truck_footprint')
local Map=require('src.commute.driving_map')
local Options=require('src.commute.island_options')
local Codec=require('src.net.codec')
local Test={}
local function same(a,b)return math.abs(a[1]-b[1])+math.abs(a[2]-b[2])<.002 end
local function length(a,b)return math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)end

function Test.run(check)
    local cases={{seed=712345},{seed=712346},{seed=42,roads=1,river=3},
        {seed=3,roads=3,elevation=3,river=4},{seed=99,roads=2,elevation=1,river=1}}
    for _,case in ipairs(cases) do
        local town=assert(Town.generate(case.seed,{island=Options.copy(case)}))
        local world=Town.world(town)
        local suffix='_'..case.seed..'_'..(case.roads or 2)
        local widths,connector=true,nil
        for _,r in ipairs(town.roads) do
            if r.role=='main' or r.role=='local' then
                widths=widths and r.lanes>=2 and not r.oneWay and r.width>=6.6 and r.width<=9.8
            end
            if r.id==town.mainlandExit.roadId then connector=r end
        end
        check('road_generation_public_streets_have_usable_two_way_lanes'..suffix,widths)
        local tangent=false
        for _,r in ipairs(town.roads) do
            if r~=connector and r.role=='main' then
                for _,index in ipairs({1,#r.points}) do
                    if same(r.points[index],connector.points[1]) then
                        local p,n=r.points[index],r.points[index==1 and 2 or index-1]
                        local a,b=connector.points[1],connector.points[2]
                        local dot=((p[1]-n[1])*(b[1]-a[1])+(p[2]-n[2])*(b[2]-a[2]))/(length(p,n)*length(a,b))
                        tangent=tangent or dot>.9999
                    end
                end
            end
        end
        check('road_generation_millhaven_approach_continues_street_tangent'..suffix,tangent)
        local lanesClear,bridgeCount=true,0
        local laneError,peakGrade=0,0
        for _,s in ipairs(world.roads.segments) do
            if (s.role=='main' or s.role=='local') and not s.truckOnly then
                peakGrade=math.max(peakGrade,math.abs(s.b.h-s.a.h)/s.len)
                if s.bridge then
                    bridgeCount=bridgeCount+1
                    local cx,cz=(s.a.x+s.b.x)*.5,(s.a.z+s.b.z)*.5
                    for _,model in ipairs({'box','kei'}) do
                        local truck={model=model}
                        local offset=Rules.laneOffset(s,'right',false,truck)
                        local dim=Footprint.dimensions(model)
                        lanesClear=lanesClear and offset>dim.halfWidth+.1
                            and offset+dim.halfWidth+.1<s.width*.5
                        -- Sample away from junctions and the off-map portal,
                        -- where the truck spans neighboring road segments.
                        local finish=town.mainlandExit
                        local nearPortal=(cx-finish.x)^2+(cz-finish.z)^2<25
                        local nearJunction=false
                        for _,j in ipairs(world.roads.junctions) do
                            if (cx-j.x)^2+(cz-j.z)^2<(j.radius+5)^2 then nearJunction=true;break end
                        end
                        if not nearPortal and not nearJunction then
                            for _,sign in ipairs({-1,1}) do
                                local heading=math.atan2(s.dz,s.dx)+(sign<0 and math.pi or 0)
                                local x,z=Rules.lanePoint({x=cx,z=cz},heading,offset)
                                lanesClear=lanesClear and not Truck.blocked(world,x,z,heading,truck)
                                laneError=math.max(laneError,math.abs(world:supportHeight(x,z)-(s.a.h+s.b.h)*.5))
                            end
                        end
                    end
                end
            end
        end
        check('road_generation_bridge_lanes_fit_opposing_box_and_kei_trucks'..suffix,
            lanesClear and bridgeCount>0,'bridges='..bridgeCount)
        check('road_generation_lane_surfaces_follow_graded_geometry'..suffix,peakGrade<.061 and laneError<.03,
            ('grade=%.5f laneHeightError=%.5f'):format(peakGrade,laneError))
        local routes=Routes.new(world.roads,{pavedOnly=true})
        local allRoutes=true
        for from in pairs(town.destinations) do for to in pairs(town.destinations) do
            if from~=to then allRoutes=allRoutes and routes:find(from,to)~=nil end
        end end
        local onRoad,maxDistance=true,0
        for i=1,#town.drivingMap.points,3 do
            local x,z,h=unpack(town.drivingMap.points,i,i+2)
            local d,s,surface=world.roads:sample(x,z)
            maxDistance=math.max(maxDistance,d)
            onRoad=onRoad and s~=nil and d<.01 and math.abs(surface-h)<.04
        end
        check('road_generation_compiled_ai_routes_share_exact_road_nodes'..suffix,
            allRoutes and onRoad and Map.valid(town,town.drivingMap),'maxDistance='..maxDistance)
        if case.seed==712345 then
            for _,pair in ipairs({{'diner','coffee-shop'},{'fire-station','brick-walkup'}}) do
                local route=assert(routes:find(pair[1],pair[2]))
                for _,model in ipairs({'box','kei'}) do
                    local a,b=route.points[1],route.points[2]
                    local truck=Truck.new(a.x,a.z,math.atan2(b.z-a.z,b.x-a.x),'plain',model)
                    local arrived=false
                    for _=1,math.ceil((route.length/3+45)*10) do
                        if require('src.commute.delivery_traffic').driveRoute(truck,route.points,.1,world,
                            pair[1]..'->'..pair[2]) then arrived=true;break end
                    end
                    local finish=route.points[#route.points]
                    check('road_generation_ai_rounds_offset_lane_turn_'..model..'_'..pair[1],arrived
                        and (truck.x-finish.x)^2+(truck.z-finish.z)^2<1.21,
                        ('position=%.1f,%.1f index=%s'):format(truck.x,truck.z,tostring(truck.pathIndex)))
                end
            end
        end
        local fingerprint=Town.fingerprint(town)
        local packet=assert(Codec.encode(town,require('src.commute.tests.town_test').codecLimits))
        local restored=assert(Codec.decode(packet,require('src.commute.tests.town_test').codecLimits))
        local loaded=Town.world(restored)
        check('road_generation_reload_keeps_geometry_and_ai_map'..suffix,
            Town.valid(restored) and Town.fingerprint(restored)==fingerprint
            and loaded.roads.drivingMap and assert(Codec.encode(restored.drivingMap,
                require('src.commute.tests.town_test').codecLimits))==assert(Codec.encode(town.drivingMap,
                require('src.commute.tests.town_test').codecLimits)))
    end
    -- The land is shaped around the designed elevation after road planning.
    local sites={all={},byId={},grade=function(_,base)return base end,foundationHeight=function()end}
    local definition={id='graded-road',width=7.6,role='main',lanes=2,surface='paved',
        interpolation='linear',points={{100,100,10},{200,100,10}},bridgeEdges={false}}
    local road=Roads.new({definitions={definition},sites=sites,destinations={},broadEarthworks=true})
    local prior=10;local graded=true
    for offset=0,24,.25 do
        local h=road:grade(2,150,100+offset)
        graded=graded and h<=prior+1e-7 and h>=2 and h<=10
        prior=h
    end
    check('road_generation_earthworks_blend_outside_road_without_shoulder_cliff',graded
        and road:grade(2,150,111)>2 and road:grade(2,150,124)==2 and road:grade(2,150,100)==10)
    local old=assert(Town.generate(712345,{generatorVersion=11}))
    local oldWorld=Town.world(old)
    check('road_generation_previous_frozen_layout_policy_remains_available',old.generatorVersion==11
        and Town.valid(old) and not oldWorld.roads.broadEarthworks)
end
return Test
