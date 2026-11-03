-- Graph/physical/frozen-data contracts for new towns, rather than generator internals.
local Town=require('src.commute.town')
local Routes=require('src.commute.routes')
local Codec=require('src.net.codec')
local TerrainV2=require('src.commute.town_terrain_v2')
local Test={}
local seeds={1,2,3,4,5,42,99,4261,712345,712346,101010,Town.MAX_SEED,12,58,100,2026101098,2049425470,609997962}
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local function graph(roads)
    local routes=Routes.new(roads);local edges,nodes,degrees=0,0,{}
    for _,node in pairs(routes.nodes)do
        nodes=nodes+1;edges=edges+#node.edges
        if #node.edges~=2 then degrees[#node.edges]=(degrees[#node.edges]or 0)+1 end
    end
    local signature={};for i=1,10 do signature[#signature+1]=degrees[i]or 0 end
    return routes,edges/2-nodes+1,table.concat(signature,':')
end
local function physical(world,routes)
    local roads=world.roads
    for _,segment in ipairs(roads.segments)do
        local x,z=(segment.a.x+segment.b.x)*.5,(segment.a.z+segment.b.z)*.5
        if roads:blocked(world,x,z)then return false,'blocked center '..segment.id end
        for _,side in ipairs({-1,1})do
            local offset=side*(segment.width*.5-.3)
            if roads:blocked(world,x+segment.nx*offset,z+segment.nz*offset)then return false,'blocked lane '..segment.id end
        end
        if math.abs(segment.a.h-segment.b.h)/segment.len>.42 then return false,'unsafe road grade' end
    end
    local Trip=require('src.commute.trip');local Rider=require('src.commute.rider');local Bike=require('src.commute.motorcycle')
    for id,pad in pairs(roads.destinations)do
        if not routes:find('warehouse',id)then return false,'unreachable '..id end
        local door=world.sites.byId[id].door
        for i=0,12 do
            local u=i/12
            if roads:blocked(world,pad.x+(door.x-pad.x)*u,pad.z+(door.z-pad.z)*u)then return false,'blocked entrance '..id end
        end
        for slot=1,4 do
            local anchor=Trip.parking(world,id,slot)
            if not anchor or not Rider.clear(world,anchor.x,anchor.z,Bike.RADIUS)
                or not Rider.clear(world,anchor.pedX,anchor.pedZ,Rider.RADIUS)then return false,'blocked parking '..id end
            if math.abs(world:supportHeight(anchor.x,anchor.z)-world:supportHeight(anchor.pedX,anchor.pedZ))>=.45 then return false,'parking drop '..id end
        end
    end
    return true
end
Test.physical=physical
function Test.run(check)
    local loops,degrees,families,lakeCounts,waterShapes,relief={},{},{},{},{},{}
    local sample,sampleWorld
    for _,seed in ipairs(seeds)do
        local town=assert(Town.generate(seed,{generatorVersion=2}));local world=Town.world(town)
        local routes,cycles,degree=graph(world.roads)
        loops[cycles]=true;degrees[degree]=true;families[town.terrain.family]=true;lakeCounts[#town.terrain.lakes]=true
        waterShapes[Town.fingerprint({rivers=town.terrain.rivers,lakes=town.terrain.lakes})]=true
        local low,high=math.huge,-math.huge
        for _,h in ipairs(town.terrain.heights)do low,high=math.min(low,h),math.max(high,h)end
        relief[math.floor(high-low)]=true
        local okay,reason=physical(world,routes)
        check('town_v2_all_routes_lanes_doors_and_guest_slots_'..seed,okay,reason)
        assert(town.generatorVersion==2 and #town.placements==16 and #town.roads<=96)
        sample,sampleWorld=town,world
    end
    local uneven=require('src.commute.roads').new({definitions={{id='uneven-junctions',width=6,interpolation='linear',
        points={{80,80,3},{160,80,4},{161,80,4.0125},{240,80,5}},bridgeEdges={false,false,false}}}})
    local monotone=true
    for _,s in ipairs(uneven.segments)do monotone=monotone and s.b.x>s.a.x and math.abs(s.b.h-s.a.h)/s.len<.02 end
    check('town_v2_uneven_junction_spacing_cannot_reverse_roads_or_create_grade_spikes',monotone)
    check('town_v2_seeds_change_independent_road_cycle_counts',count(loops)>=4)
    check('town_v2_seeds_change_actual_junction_degree_topology',count(degrees)>=5)
    check('town_v2_seeds_change_waterway_families_lakes_and_geometry',count(families)==4 and count(lakeCounts)>=3 and count(waterShapes)==#seeds)
    check('town_v2_seeds_change_relief_range',count(relief)>=4)
    local packet=assert(Codec.encode(sample,{maxBytes=524288,maxEntries=32768}))
    local frozen=assert(Codec.decode(packet,{maxBytes=524288,maxEntries=32768}))
    local expected={}
    for x=80,440,60 do for z=80,440,60 do expected[#expected+1]={x,z,sampleWorld:height(x,z),sampleWorld.plan:waterIdAt(x,z)}end end
    local generator=TerrainV2.generate;local oldPlan=require('src.commute.vendor.island_plan');local oldNew=oldPlan.newTown
    TerrainV2.generate=function()error('Reload called new generator')end
    oldPlan.newTown=function()error('Reload called legacy generator')end
    local okay,loaded=pcall(Town.world,frozen)
    TerrainV2.generate=generator;oldPlan.newTown=oldNew
    local identical=okay
    if okay then for _,p in ipairs(expected)do
        identical=identical and loaded:height(p[1],p[2])==p[3] and loaded.plan:waterIdAt(p[1],p[2])==p[4]
    end end
    check('town_v2_reload_uses_only_frozen_heights_and_waterways',identical)
    check('town_v2_world_loading_preserves_all_saved_data',assert(Codec.encode(frozen,{maxBytes=524288,maxEntries=32768}))==packet)
    local h=loaded.plan.grid[0][0];local rx=loaded.plan.rivers[1].points[1].x
    frozen.terrain.heights[1]=h+1;frozen.terrain.rivers[1].points[1].x=rx+10
    check('town_v2_world_detaches_frozen_terrain_arrays',loaded.plan.grid[0][0]==h and loaded.plan.rivers[1].points[1].x==rx)
    local function rejected(edit)local bad=Town.copy(sample);edit(bad);return not Town.valid(bad)end
    check('town_v2_rejects_invalid_saved_waterways',rejected(function(t)t.terrain.rivers[1].waterWidth=100 end)
        and rejected(function(t)t.terrain.rivers[1].points[2]=Town.copy(t.terrain.rivers[1].points[1])end)
        and rejected(function(t)t.terrain.rivers[1].points[1].x=math.huge end))
    check('town_v2_rejects_invalid_saved_relief_and_lakes',rejected(function(t)t.terrain.heights[1]=0/0 end)
        and rejected(function(t)t.terrain.lakes[1]={id='bad',x=200,z=200,rx=0,rz=10,depth=1,angle=0}end))
    local legacy=Town.legacy();local old=assert(Town.generate(712345,{generatorVersion=1}))
    local oldWorld=Town.world(old);local legacyWorld=Town.world(legacy)
    check('town_v2_preserves_v0_and_v1_world_interpretation',legacy.generatorVersion==0 and old.generatorVersion==1
        and oldWorld.plan.townPreset=='inland-town-v1' and legacyWorld:riverCenterX(270)==330
        and oldWorld.plan.grid[1][54]==old.terrain.heights[120])
end
return Test
