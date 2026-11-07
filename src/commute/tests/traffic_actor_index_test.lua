local Index=require('src.commute.traffic_actor_index')
local Test={}

function Test.run(check)
    local entries={}
    for index=1,10 do
        entries[index]={id=index,actor={x=(index-1)*15,z=0}}
    end
    local index=Index.new(entries,10)
    local nearby=index:queryCircle(15,0,15)
    local boxed=index:queryBox(-1,-1,31,1)
    local streamedOrder={}
    local streamCompleted=index:forEachBox(-1,-1,31,1,function(entry,order)
        streamedOrder[#streamedOrder+1]=entry.id..':'..order
    end)
    local visitedBeforeStop=0
    local earlyCompleted=index:forEachBox(-1,-1,31,1,function()
        visitedBeforeStop=visitedBeforeStop+1
        return false
    end)
    entries[10].actor.x=15
    local updated=index:update(entries[10].actor)
    local moved=index:queryCircle(15,0,0)
    local diagonalForward={id='forward',actor={x=math.sqrt(.5)*100,z=math.sqrt(.5)*100}}
    local diagonalEdge={id='edge',actor={x=math.sqrt(.5)*97,z=math.sqrt(.5)*103}}
    local diagonalOutside={id='outside',actor={x=math.sqrt(.5)*92,z=math.sqrt(.5)*108}}
    local diagonalCorner={id='corner',actor={x=-100,z=100}}
    local corridorIndex=Index.new({diagonalForward,diagonalEdge,diagonalOutside,diagonalCorner},10)
    local corridorIds={}
    local corridorCompleted=corridorIndex:forEachOrientedBox(0,0,math.pi/4,150,4,function(entry)
        corridorIds[#corridorIds+1]=entry.id
    end)
    table.sort(corridorIds)
    check('traffic_actor_index_filters_by_space_and_tracks_movement',index.count==10
        and #nearby==3 and nearby[1].id==1 and nearby[2].id==2 and nearby[3].id==3
        and #boxed==3 and boxed[1].id==1 and boxed[2].id==2 and boxed[3].id==3
        and streamCompleted and table.concat(streamedOrder,',')=='1:1,2:2,3:3'
        and not earlyCompleted and visitedBeforeStop==1
        and updated and #moved==2 and moved[1].id==2 and moved[2].id==10)
    check('traffic_actor_index_visits_only_actors_inside_a_rotated_road_corridor',
        corridorCompleted and table.concat(corridorIds,',')=='edge,forward')

    local denseEntries={}
    for row=1,20 do
        for column=1,20 do
            local id=(row-1)*20+column
            denseEntries[id]={id=id,actor={x=(column-1)*15,z=(row-1)*15}}
        end
    end
    local denseIndex=Index.new(denseEntries)
    local denseNearby=denseIndex:queryCircle(142.5,142.5,32)
    local broadCorridorCandidates,orientedCorridorCandidates=0,0
    denseIndex:forEachBox(30.8,30.8,254.2,254.2,function()broadCorridorCandidates=broadCorridorCandidates+1 end)
    denseIndex:forEachOrientedBox(142.5,142.5,math.pi/4,150,8,
        function()orientedCorridorCandidates=orientedCorridorCandidates+1 end)
    print(('AI_TRAFFIC_INDEX_CANDIDATES actors=%d candidates=%d'):format(denseIndex.count,#denseNearby))
    print(('AI_TRAFFIC_CORRIDOR_CANDIDATES broad=%d oriented=%d'):
        format(broadCorridorCandidates,orientedCorridorCandidates))
    check('traffic_actor_index_reduces_dense_world_candidates',
        not Index.shouldUse(Index.MIN_ACTORS-1) and Index.shouldUse(Index.MIN_ACTORS)
            and denseIndex.count==400 and #denseNearby<denseIndex.count*.1)
    check('traffic_actor_index_reduces_diagonal_corridor_candidates',
        broadCorridorCandidates>orientedCorridorCandidates*4 and orientedCorridorCandidates>0)
end

return Test
