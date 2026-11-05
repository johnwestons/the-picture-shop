local Town=require('src.commute.town')
local Cache=require('src.commute.terrain_cache')
local Ground=require('src.commute.ground_textures')
local Test={}

function Test.run(check)
    local town=assert(Town.generate(973401))
    local job=Cache.bake(town)
    local wasCached=job.done
    local deadline=love.timer.getTime()+90
    while not job.done do
        job:step(.008)
        assert(love.timer.getTime()<deadline,'Terrain bake exceeded 90 seconds')
    end
    check('terrain_cache_new_town_bakes_complete_manifest',not job.failed
        and Cache.available(job.store) and (wasCached or job.mesh.ready and job.mesh.completed==484))
    check('terrain_cache_new_town_bake_has_expected_sample_count',job.mesh.sampleCount>0 or wasCached)

    local tiles=job.mesh.tiles
    local first,last=tiles[1],tiles[#tiles]
    local a=assert(Cache.readTile(job.store,first))
    local b=assert(Cache.readTile(job.store,last))
    check('terrain_cache_reads_independent_town_tiles',a.vertexCount==(first.nx+1)*(first.nz+1)
        and b.vertexCount==(last.nx+1)*(last.nz+1)
        and a.indexCount==first.nx*first.nz*6 and b.indexCount==last.nx*last.nz*6)

    local mesh=love.graphics.newMesh(Ground.FORMAT,a.vertexCount,'triangles','static')
    mesh:setVertices(a.vertices)
    mesh:setVertexMap(a.indices,'uint32')
    local x,z=mesh:getVertex(1)
    check('terrain_cache_uploads_binary_mesh_to_gpu',mesh:getVertexCount()==a.vertexCount
        and math.abs(x-first.x0)<.001 and math.abs(z-first.z0)<.001)
    mesh:release()

    local nextJob=Cache.bake(town)
    check('terrain_cache_reuses_matching_world_on_next_creation',nextJob.done and not nextJob.failed)
end

return Test
