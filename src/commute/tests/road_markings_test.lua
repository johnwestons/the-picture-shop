-- Exercise the triangles uploaded to both cameras, with distinguishable lane
-- elevations and wet/dirt exclusions rather than relying on a screenshot alone.
local Paint=require('src.commute.road_markings')
local Roads=require('src.commute.roads')
local Test={}
local function close(a,b)return math.abs(a-b)<.000001 end
local function height(x)return 3+.16*(x-10) end
local function road(id,z,width,role,lanes,oneWay,turn,bridge)
    return {id=id,role=role,surface=role=='trail' and 'dirt' or 'paved',lanes=lanes,
        oneWay=oneWay,turnLane=turn,width=width,interpolation='linear',
        points={{10,z,height(10)},{100,z,height(100)}},bridgeEdges={bridge or false}}
end
local function world()
    local definitions={road('main',20,9.8,'main',3,false,true),
        road('one-way',60,4.2,'local',1,true,false),road('woods',100,2.8,'trail',1,false,false),
        road('local',140,6,'local',2,false,false),road('bridge',180,6,'local',2,false,false,true)}
    local roads=Roads.new({definitions=definitions,destinations={}})
    local w={roads=roads,town={generatorVersion=3},infrastructure={fixtures={
        {kind='stop',stopX=82,stopZ=60,fx=-1,fz=0,roadWidth=4.2,oneWay=true},
        {kind='stop',stopX=30,stopZ=140,fx=1,fz=0,roadWidth=6,oneWay=false}}}}
    function w:supportHeight(x,z)return height(x)end
    return w
end
function Test.run(check)
    local w=world()
    local vertices,stats=Paint.build(w)
    local insideLanes,cleanSurfaces,plainPaint,followingGrade=true,true,true,true
    local oneMin,oneMax,twoMin,twoMax=math.huge,-math.huge,math.huge,-math.huge
    local arrowVertices,barVertices=0,0
    for _,v in ipairs(vertices) do
        local x,z,y=v[1],v[2],v[3]
        local d,segment=w.roads:nearest(x,z)
        insideLanes=insideLanes and segment and d<=segment.width*.5 and x>=10 and x<=100
        cleanSurfaces=cleanSurfaces and segment and segment.surface~='dirt' and not segment.bridge
        local lift=y-w:supportHeight(x,z)
        followingGrade=followingGrade and lift>=.07499 and lift<=.09001
        if close(lift,.085) then arrowVertices=arrowVertices+1 end
        if close(lift,.09) then
            barVertices=barVertices+1
            if segment.id=='one-way' then oneMin,oneMax=math.min(oneMin,z),math.max(oneMax,z)
            elseif segment.id=='local' then twoMin,twoMax=math.min(twoMin,z),math.max(twoMax,z) end
        end
        plainPaint=plainPaint and #v==24 and v[13]>.8 and v[14]>.6 and v[16]==1
            and v[17]==0 and v[18]==0 and v[19]==0 and v[20]==0 and v[24]==0
    end
    check('road_markings_all_triangles_stay_on_their_paved_lane_surface',
        #vertices>0 and #vertices%3==0 and insideLanes and cleanSurfaces)
    check('road_markings_straight_and_turn_arrows_follow_sixteen_percent_grade',
        followingGrade and stats.arrows>0 and stats.turnArrows>0 and arrowVertices>0)
    check('road_markings_use_visible_opaque_vertex_paint_without_material_or_water',
        plainPaint)
    check('road_markings_one_way_stop_bar_spans_full_lane',stats.stopBars==2 and barVertices==12
        and close(oneMin,60-1.9) and close(oneMax,60+1.9))
    check('road_markings_two_way_stop_bar_only_covers_right_hand_approach',
        close(twoMin,140-2.8) and close(twoMax,140-.2))
end
return Test
