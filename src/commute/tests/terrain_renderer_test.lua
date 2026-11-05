local Renderer=require('src.commute.renderer')
local Mesh=require('src.commute.terrain_mesh')
local Test={}
function Test.run(check)
    check('mobile_commute_limits_foliage_distance_and_keeps_nearby_plants',
        Renderer.foliageRadius(96,true)==72 and Renderer.foliageRadius(48,true)==48
            and Renderer.foliageRadius(96,false)==96)
    local oldMesh,oldClock,oldBudget=love.graphics.newMesh,love.timer.getTime,Renderer.LOAD_BUDGET_SECONDS
    local elapsed,created,releases=0,0,0
    local resources={}
    local function resource()
        local value={released=0,release=function(self)self.released=self.released+1;releases=releases+1 end}
        resources[#resources+1]=value;return value
    end
    local okay,reason=xpcall(function()
        love.timer.getTime=function()return elapsed end
        love.graphics.newMesh=function(_,vertices)
            created=created+1
            local mesh=resource();mesh.vertices=#vertices
            function mesh:setVertexMap(indices)self.indices=#indices end
            return mesh
        end
        local world={size=50,height=function(_,x,z)return 2+x*.01+z*.02 end}
        local t=Mesh.new(world,{tileSize=24,spacing=1,surface=function()
            elapsed=elapsed+.0001;return .3,.5,.2,'grass',1,0,0,1,.5,.5,.5
        end})
        local propsCalls,projected=0,0
        local renderer=setmetatable({world=world,terrain=t,chunks={},visible={},terrainVertices=0,
            terrainIndices=0,radius=64,clock=0,serial=0,calendar={},
            plantMotion={update=function()end},plantSprites=resource(),bikeArt=resource(),
            structures=resource(),roadMeshes={resource(),resource()},ground=resource(),
            firstPersonView=resource(),props=function()propsCalls=propsCalls+1;return {}end},Renderer)
        renderer.plantSprites.prepare=function()end
        local camera={firstPerson=false,centerX=0,centerZ=0,zoom=.55,tilt=20,
            depth=function(_,x,z,h)projected=projected+1;return x+z+h end}
        check('terrain_renderer_cold_surface_has_no_claimed_coverage',not renderer:terrainReady()
            and not renderer:terrainCoverage(0,0) and renderer:terrainStats().uncovered==9)
        Renderer.LOAD_BUDGET_SECONDS=0;renderer:prepare(camera,1/60)
        check('terrain_renderer_empty_budget_keeps_surface_closed',not renderer:terrainReady()
            and #renderer.visible==0 and created==0 and propsCalls==0)
        Renderer.LOAD_BUDGET_SECONDS=.012;renderer:prepare(camera,1/60)
        check('terrain_renderer_partial_build_is_not_ready',not renderer:terrainReady()
            and t.job and t.completed==0 and propsCalls==0 and renderer.pending==9)
        local frames=1
        while not renderer:terrainReady() and frames<1000 do renderer:prepare(camera,1/60);frames=frames+1 end
        local stats=renderer:terrainStats()
        check('terrain_renderer_complete_residency_has_bounded_gpu_storage',stats.ready and stats.total==9
            and stats.completed==9 and stats.uncovered==0 and stats.submitted==9 and created==9
            and stats.vertices==t.vertexCount and stats.meshBytes==t.vertexCount*96+t.indexCount*4)
        local corners=renderer:terrainCoverage(0,0) and renderer:terrainCoverage(50,50)
            and renderer:terrainCoverage(0,50) and renderer:terrainCoverage(50,0)
        check('terrain_renderer_covers_world_edges_and_rejects_outside',corners
            and not renderer:terrainCoverage(-.001,0) and not renderer:terrainCoverage(50.001,50))
        local samples=t.sampleCount;local original={}
        for key,tile in pairs(renderer.chunks)do original[key]=tile.mesh end
        local stable,linear=true,true
        for frame=1,360 do
            -- Include the old eviction threshold, rapid reversal, far movement,
            -- widest zoom and steep first-person look. These cannot touch mesh residency.
            camera.firstPerson=frame%2==0;camera.zoom=frame%3==0 and .55 or 1.5
            camera.centerX=frame%50;camera.centerZ=(frame*17)%50
            camera.viewCos=frame%2==0 and -1 or 1;camera.viewSin=0;camera.viewSlope=1
            camera.viewPitch=-math.pi/2;projected=0
            renderer:prepare(camera,1/120)
            linear=linear and projected==9
            stable=stable and #renderer.visible==9 and renderer:terrainCoverage(0,0)
                and renderer:terrainCoverage(50,50) and renderer.pending==0 and renderer.buildMs==0
            for key,tile in pairs(renderer.chunks)do stable=stable and original[key]==tile.mesh end
        end
        check('terrain_renderer_camera_changes_never_rebuild_or_evict_surface',stable and created==9
            and releases==0 and t.sampleCount==samples)
        check('terrain_renderer_sort_projects_each_resident_tile_once',linear)
        renderer:release();renderer:release()
        local releasedOnce=true
        for _,entry in ipairs(resources)do releasedOnce=releasedOnce and entry.released==1 end
        check('terrain_renderer_release_frees_every_resource_once',releasedOnce)
        check('terrain_renderer_release_clears_coverage_and_partial_work',not renderer:terrainReady()
            and not renderer:terrainCoverage(0,0) and next(renderer.chunks)==nil and #renderer.visible==0)
    end,debug.traceback)
    love.graphics.newMesh,love.timer.getTime,Renderer.LOAD_BUDGET_SECONDS=oldMesh,oldClock,oldBudget
    if not okay then error(reason,0)end
end
return Test
