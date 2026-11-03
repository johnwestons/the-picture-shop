local Mesh=require('src.commute.terrain_mesh')
local Test={}
local function near(a,b)return math.abs(a-b)<.000001 end
local function color()return .3,.5,.2,'grass',1,0,0,1,.5,.5,.5 end
local function plane(size)
    return {size=size,height=function(_,x,z)return 2+x*.02+z*.03 end}
end
local function equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
function Test.run(check)
    local elapsed=0
    local stepped=Mesh.new(plane(8),{tileSize=4,spacing=1,surface=function(...)
        elapsed=elapsed+.001;return color(...)
    end})
    local clock=function()return elapsed end
    local uploads={};local function upload(tile,vertices,indices)
        uploads[tile.key]={vertices=vertices,indices=indices}
    end
    local ready,finished=stepped:step(0,upload,clock)
    check('terrain_residency_zero_budget_never_opens_gate',not ready and finished==0
        and stepped.completed==0 and stepped.sampleCount==0 and next(uploads)==nil)
    stepped:step(.002,upload,clock)
    check('terrain_residency_yields_after_one_indivisible_row',stepped.job and stepped.job.row==1
        and stepped.sampleCount==5 and stepped.completed==0 and next(uploads)==nil and stepped.lastBuildMs>=5)
    local steps=1
    while not stepped.ready and steps<100 do stepped:step(.002,upload,clock);steps=steps+1 end
    local direct=Mesh.new(plane(8),{tileSize=4,spacing=1,surface=color})
    local expected={};direct:step(1,function(tile,vertices,indices)
        expected[tile.key]={vertices=vertices,indices=indices}
    end,function()return 0 end)
    check('terrain_residency_incremental_geometry_matches_single_pass',stepped.ready and direct.ready
        and steps==20 and equal(uploads,expected))
    local beforeSamples,beforeUploads=stepped.sampleCount,stepped.completed
    stepped:step(1,function()error('Completed terrain uploaded twice')end,clock)
    check('terrain_residency_completed_step_has_no_new_work',stepped.sampleCount==beforeSamples
        and stepped.completed==beforeUploads and stepped.job==nil)

    local world=plane(512);local all=Mesh.new(world,{tileSize=24,spacing=1,surface=color})
    check('terrain_residency_constructor_is_lazy_and_covers_all_tiles',all.total==484 and all.completed==0
        and all.sampleCount==0 and not all.ready and all.job==nil)
    local area,valid,seams,edgeX,edgeZ,last=0,true,{},false,false,false
    local seamOkay=true;local callbacks=0
    all:step(1,function(tile,vertices,indices)
        callbacks=callbacks+1
        valid=valid and tile.x0>=0 and tile.z0>=0 and tile.x1<=512 and tile.z1<=512
            and near(tile.centerX,(tile.x0+tile.x1)/2) and near(tile.centerZ,(tile.z0+tile.z1)/2)
        for _,v in ipairs(vertices)do
            valid=valid and v[1]>=tile.x0 and v[1]<=tile.x1 and v[2]>=tile.z0 and v[2]<=tile.z1
                and near(v[3],world:height(v[1],v[2]))
            edgeX=edgeX or v[1]==512;edgeZ=edgeZ or v[2]==512
            if v[1]==tile.x0 or v[1]==tile.x1 or v[2]==tile.z0 or v[2]==tile.z1 then
                local key=v[1]..':'..v[2];local old=seams[key]
                if old then for k=3,6 do seamOkay=seamOkay and near(old[k],v[k])end
                else seams[key]=v end
            end
        end
        for i=1,#indices,3 do
            local a,b,c=vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]
            if not(a and b and c)then valid=false
            else
                local cross=(b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1])
                valid=valid and cross>0;area=area+cross/2
            end
        end
        if tile.x0==504 and tile.z0==504 then
            last=tile.x1==512 and tile.z1==512 and tile.centerX==508 and tile.centerZ==508
                and #vertices==81 and #indices==384
        end
    end,function()return 0 end)
    check('terrain_residency_full_map_triangles_cover_exact_area',valid and near(area,512*512)
        and all.ready and all.completed==484 and callbacks==484)
    check('terrain_residency_partial_edge_tiles_reach_world_boundary',edgeX and edgeZ and last)
    check('terrain_residency_adjacent_tiles_share_identical_height_and_normal',seamOkay)
    local retained=false
    for _,tile in ipairs(all.tiles)do retained=retained or tile.vertices~=nil or tile.indices~=nil end
    check('terrain_residency_discards_uploaded_cpu_arrays',not retained and all.job==nil
        and all.vertexCount==285156 and all.indexCount==1572864 and all.sampleCount==285156)
    check('terrain_residency_reuses_exact_gradient_height_samples',all.cacheHits>0
        and all.heightSamples<all.sampleCount*5)

    -- Translate a real legacy riverbank/deck section into a small test world.
    -- Geometry still samples the production Terrain + Roads height contracts.
    local roads=require('src.commute.roads').new()
    local terrain=roads:attach(require('src.commute.terrain').new())
    local bridge={size=6,height=function(_,x,z)return terrain:height(x+354,z+270)end,
        supportHeight=function(_,x,z)return terrain:supportHeight(x+354,z+270)end,
        roads={sample=function(_,x,z)return roads:sample(x+354,z+270)end}}
    local inspected,clear=0,true
    Mesh.new(bridge,{tileSize=6,spacing=1,surface=color}):step(1,function(_,vertices)
        for _,v in ipairs(vertices)do
            local support,kind=bridge:supportHeight(v[1],v[2])
            if kind=='bridge'then inspected=inspected+1;clear=clear and v[3]<support end
        end
    end,function()return 0 end)
    check('terrain_residency_bridge_mesh_keeps_riverbank_below_deck',inspected>0 and clear)
    local low={a={x=0,z=0,h=3},b={x=10,z=0,h=3},dx=10,dz=0,length2=100,width=4}
    local high={a={x=0,z=0,h=5},b={x=10,z=0,h=5},dx=10,dz=0,length2=100,width=4}
    local overlap={roads={bins={['0:0']={high,low}},binSize=16}}
    check('terrain_residency_overlapping_roads_use_lowest_visible_surface',near(Mesh.visualHeight(overlap,5,0,7,1),2.92))
    check('terrain_residency_road_cell_guard_preserves_remote_terrain',near(Mesh.visualHeight(overlap,5,3,7,1),2.92)
        and Mesh.visualHeight(overlap,5,4,7,1)==7)
    local failed=Mesh.new(plane(1),{tileSize=1,spacing=1,surface=color})
    local okay=pcall(function()failed:step(1,function()error('Simulated upload failure')end,function()return 0 end)end)
    check('terrain_residency_upload_failure_cannot_mark_tile_ready',not okay and not failed.ready
        and failed.completed==0 and not failed.tiles[1].ready)
    local retriedVertices=0
    failed:step(1,function(_,vertices)retriedVertices=#vertices end,function()return 0 end)
    check('terrain_residency_failed_upload_retries_without_duplicate_rows',failed.ready
        and failed.completed==1 and failed.sampleCount==4 and retriedVertices==4)
end
return Test
