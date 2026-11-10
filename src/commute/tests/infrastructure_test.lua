local Roads=require('src.commute.roads')
local Infrastructure=require('src.commute.infrastructure')
local Geometry=require('src.commute.infrastructure_geometry')
local Test={}
local function road(id,role,width,points)
    return {id=id,role=role,width=width,points=points,surface='paved',
        interpolation='linear',sidewalks=role=='main' or role=='local',bridgeEdges={}}
end
local function fixtureWorld()
    local roads={
        road('main-a','main',8,{{20,50,5},{35,50,5},{70,50,5}}),
        road('main-b','main',8,{{70,50,5},{104,50,5}}),
        road('cross','local',5.5,{{70,14,5},{70,50,5}}),
        road('bend','local',5.5,{{20,50,5},{20,15,5}}),
        road('residential-1-drive','drive',3.5,{{35,50,5},{35,63,5}})}
    local house={parking={x=35,z=63},distance=function(_,x,z)return math.sqrt((x-35)^2+(z-73)^2)-5 end}
    local registry={all={house},blocked=function()return false end}
    local w={town={seed=123,generatorVersion=3,roads=roads,
        placements={{id='residential-1',frontageRoadId='main-a',district='residential',origin={x=35,z=73}}},
        recreation={{kind='camp',x=87,z=75,radius=5.5},{kind='picnic',x=45,z=25,radius=5.5},
            {kind='park',x=48,z=75,radius=5.5}}},sites=registry}
    w.roads=Roads.new({definitions=roads,sites=registry,destinations={},bounds={x0=0,z0=0,x1=120,z1=100}})
    function w:height(x,z)
        local ravine=x>=55 and x<82 and z>60 and math.min(2.4,(z-60)*.8) or 0
        local base=5
        return base-ravine
    end
    return w
end
function Test.run(check)
    require('src.commute.tests.recreation_test').run(check)
    local world=fixtureWorld()
    local plan=Infrastructure.ensure(world)
    local count=plan.counts
    check('town_streets_sidewalks_lamps_mailboxes_are_generated',count.sidewalk>20 and count.lamp>0 and count.mailbox==1)
    check('town_streets_signs_follow_the_intersection_and_bend',count.stop==1 and count.curve==2)
    local clear=true
    for _,w in ipairs(plan.walks) do
        if w.roadId=='main-a' and w.z>50 and math.abs(w.x-35)<1.7 then clear=false end
    end
    check('town_sidewalks_leave_driveway_openings',clear)
    local sampled=plan.walks[1]
    local h=plan:sidewalkHeight(sampled.x,sampled.z)
    check('town_sidewalk_top_is_walkable_and_ends_ramp_to_the_street',h and h>world:height(sampled.x,sampled.z)
        and math.abs(sampled.corners[1][3]-world:height(sampled.corners[1][1],sampled.corners[1][2])-.025)<.00001)
    local ridgeWorld=fixtureWorld()
    local ground=ridgeWorld.height
    function ridgeWorld:height(px,pz)
        local distance=math.sqrt((px-sampled.x)^2+(pz-sampled.z)^2)
        return ground(self,px,pz)+math.max(0,1-distance)*.95
    end
    local ridgePlan=Infrastructure.new(ridgeWorld)
    local clearRidge=true
    for _,walk in ipairs(ridgePlan.walks) do
        local support=ridgePlan:sidewalkHeight(walk.x,walk.z)
        clearRidge=clearRidge and support and support>=ridgeWorld:height(walk.x,walk.z)-.01
    end
    check('town_sidewalk_subdivides_through_local_ground_rises',clearRidge and #ridgePlan.walks>#plan.walks)
    local stop
    for _,s in ipairs(plan.fixtures) do if s.kind=='stop' then stop=s end end
    check('town_stop_sign_faces_incoming_side_road_traffic',stop and stop.roadId=='cross'
        and stop.fx==0 and stop.fz==-1 and stop.x<70 and stop.z<50)
    check('town_recreation_has_camp_picnic_and_park_geometry',count.table==2 and count.bench==3
        and count.tent==1 and count.fireRing==1 and count.trailSign==3)
    local rail=assert(plan.rails[1])
    local dx,dz=rail.bx-rail.ax,rail.bz-rail.az
    local length=math.sqrt(dx*dx+dz*dz)
    local nx,nz=-dz/length,dx/length
    local x,z,h=rail.x,rail.z,(rail.ha+rail.hb)*.5
    local t,hx,hz,kind=plan:sweep(x-nx*2,z-nz*2,x+nx*2,z+nz*2,.36,h,h+1.4)
    check('town_guardrail_only_on_measured_drop_and_blocks_speeding_bike',rail.drop>1.55 and t and t>.2
        and t<.5 and hx*nx+hz*nz<-.999 and kind=='guardrail' and plan:blocked(x,z))
    check('town_rail_allows_airborne_clearance_and_leaving_overlap',
        not plan:sweep(x-nx*2,z-nz*2,x+nx*2,z+nz*2,.36,h+1.1,h+2.5)
        and not plan:sweep(x-nx*.20,z-nz*.20,x-nx*2,z-nz*2,.36,h,h+1.4))
    function world:supportHeight(px,pz)return self.roads:supportHeight(self,px,pz) end
    local Bike=require('src.commute.motorcycle')
    local bike=Bike.new(x-nx*2,z-nz*2,math.atan2(nz,nx))
    bike.speed=12;Bike.resetHorizontal(bike);Bike.resetContact(bike,world)
    for _=1,24 do Bike.update(bike,{},1/60,world) end
    local bikeRailDistance=(bike.x-x)*nx+(bike.z-z)*nz
    check('town_guardrail_stops_a_moving_motorcycle_on_the_approach_side',bike.collisionKind=='guardrail'
        and bike.speed<.05 and bikeRailDistance<0,
        string.format('kind=%s speed=%.3f railDistance=%.3f position=%.2f,%.2f rail=%.2f,%.2f grounded=%s',
            tostring(bike.collisionKind),bike.speed,bikeRailDistance,bike.x,bike.z,x,z,tostring(bike.grounded)))
    local meshes=Geometry.build(plan)
    local finite=true
    for _,mesh in ipairs(meshes) do
        finite=finite and #mesh.vertices>0 and mesh.bounds.minH<=mesh.bounds.maxH
        for _,v in ipairs(mesh.vertices) do
            finite=finite and #v==12 and v[1]==v[1] and math.abs(v[1])<10000
        end
    end
    check('town_fixture_meshes_are_finite_and_batched_by_area',finite and #meshes<#plan.walks+#plan.fixtures)
    local again=Infrastructure.new(world)
    check('town_fixture_cache_and_layout_are_repeatable',Infrastructure.ensure(world)==plan
        and #again.walks==#plan.walks and #again.rails==#plan.rails and #again.fixtures==#plan.fixtures
        and again.fixtures[1].x==plan.fixtures[1].x and again.fixtures[1].kind==plan.fixtures[1].kind)
    world.town.generatorVersion=2
    local old=Infrastructure.new(world)
    check('town_existing_frozen_layouts_keep_their_original_fixture_policy',#old.walks==0 and #old.fixtures==0)
end
return Test
