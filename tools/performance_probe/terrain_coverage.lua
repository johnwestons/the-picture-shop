-- PC acceptance: complete ground residency and visible-radius coverage on the
-- first reveal and after every jump/zoom/ride/orbit. Loading is separate.
local Audit=require('tools.performance_probe.ground_coverage_audit')
local Probe={}
local function summary(values)
    local copy,total={},0
    for i,v in ipairs(values) do copy[i]=v;total=total+v end
    table.sort(copy)
    return {mean=total/#copy,p50=copy[math.ceil(#copy*.5)],p95=copy[math.ceil(#copy*.95)],max=copy[#copy]}
end
local function terrainStats(renderer)
    local result=type(renderer.terrainStats)=='function' and renderer:terrainStats() or renderer.terrainStats
    assert(type(result)=='table','Terrain coverage probe requires renderer:terrainStats()')
    return result
end
local function residentCount(stats)return stats.resident or stats.submitted or 0 end
local function culledCount(stats)
    return stats.culled or math.max(0,residentCount(stats)-(stats.submitted or residentCount(stats)))
end
local function saveImage(output,name,pixels)
    local bytes=pixels:encode('png');local file=assert(io.open(output..'/'..name..'.png','wb'))
    file:write(bytes:getString());file:close();bytes:release();pixels:release()
end
local function pump()
    love.event.pump()
    for event in love.event.poll() do if event=='quit' then error('Terrain coverage probe interrupted') end end
end
function Probe.run(output,identity)
    local timer=love.timer.getTime
    local asyncPlantImages=os.getenv('PICTURE_SHOP_TERRAIN_ASYNC_IMAGES')=='1'
    local imageLoader=asyncPlantImages and require('src.image_loader') or nil
    if imageLoader then imageLoader.setEnabled(true) end
    local report={scenario='immediate-terrain-coverage',identity=identity,width=1280,height=880,vsync=0,
        async_plant_images=asyncPlantImages,
        rows={},startup={},failures={},samples={},complete=false,
        timing_note='Actual window draw/present; first, early and final captures use GPU readback. PNG encoding and independent world-ray audits excluded from measured frame/adjusted series timings.'}
    local api,version,vendor,device=love.graphics.getRendererInfo()
    report.graphics={name=api,version=version,vendor=vendor,device=device,os=love.system.getOS()}
    local function write()
        local file=assert(io.open(output..'/measurements.json','wb'))
        file:write(require('tools.performance_probe.json')(report));file:close()
    end
    local function check(name,okay,detail)
        report.checks=(report.checks or 0)+1
        if not okay then
            report.failed_checks=(report.failed_checks or 0)+1
            if #report.failures<64 then report.failures[#report.failures+1]={name=name,detail=detail} end
        end
    end
    local function loadingText(stats)
        love.graphics.setCanvas();love.graphics.origin();love.graphics.clear(.055,.075,.09,1)
        love.graphics.setColor(.88,.92,.92,1)
        love.graphics.print('PREPARING COMPLETE TERRAIN',44,40)
        love.graphics.print('Coverage acceptance harness: no exterior scene is shown until all ground is resident.',44,72)
        if stats then love.graphics.print(string.format('Terrain tiles: %d / %d',stats.completed or 0,stats.total or 0),44,104) end
    end
    loadingText();local loadingPixels
    love.graphics.captureScreenshot(function(data)loadingPixels=data end);love.graphics.present()
    assert(loadingPixels);saveImage(output,'loading-before-construction',loadingPixels)
    local originalNewMesh=love.graphics.newMesh;local groundAllocations=0
    love.graphics.newMesh=function(format,...)
        if type(format)=='table' and type(format[1])=='table' and type(format[1][1])=='string' then
            for _,attribute in ipairs(format) do
                if attribute[1]=='GroundNormal' then groundAllocations=groundAllocations+1;break end
            end
        end
        return originalNewMesh(format,...)
    end
    local started=timer()
    local Town=require('src.commute.town');local seed=tonumber(os.getenv('PICTURE_SHOP_TOWN_SEED')) or 1
    local town=assert(Town.generate(seed));local world=Town.world(town)
    report.startup.world_ms=(timer()-started)*1000
    report.town={seed=seed,id=town.id,generator_version=town.generatorVersion,road_segments=#world.roads.segments}
    local Renderer=require('src.commute.renderer');local Rider=require('src.commute.rider')
    local Camera=require('src.commute.camera');local FP=require('src.commute.first_person_camera')
    local Routes=require('src.commute.routes').new(world.roads)
    local origin=world.roads.destinations.warehouse
    local rider=Rider.new(origin.x,origin.z,0,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
    Rider.update(rider,{},0,world);local actor=rider.bike
    local paintId=os.getenv('PICTURE_SHOP_BIKE_PAINT')
    if paintId and paintId~='' then
        assert(require('src.commute.bike_paint').valid(paintId),'Unknown benchmark paint finish')
        actor.paintId=paintId
    end
    report.paintId=actor.paintId or 'bronze'
    local camera=Camera.new(actor,world);camera.zoom=.8;camera.targetZoom=.8
    local forceMobile=os.getenv('PICTURE_SHOP_TERRAIN_FORCE_MOBILE')=='1'
    local rendererOptions={mobile=forceMobile}
    started=timer();local renderer=Renderer.new(world,nil,rendererOptions);report.startup.renderer_ms=(timer()-started)*1000
    report.terrain_spacing=renderer.terrain.spacing
    report.terrain_cache_ready=renderer.terrainCacheReady==true
    report.terrain_cache_writable=renderer.terrainCacheWritable==true
    report.mobile_policy=renderer.mobile==true
    report.mobile_foliage_radius=Renderer.MOBILE_FOLIAGE_RADIUS
    report.ground_atlas={mobile=renderer.ground.mobile,path=renderer.ground.atlasPath,
        bytes=renderer.ground.bytes,width=renderer.ground.size}
    assert(type(renderer.terrainReady)=='function' and type(renderer.terrainCoverage)=='function',
        'Terrain coverage probe requires terrainReady() and terrainCoverage(x,z)')
    local drawCoverage=renderer.terrainDrawCoverage or renderer.terrainCoverage
    started=timer();renderer:prewarmViews()
    local cockpit=require('src.commute.cockpit').new();if cockpit.prewarmFirstPerson then cockpit:prewarmFirstPerson() end
    report.startup.view_prewarm_ms=(timer()-started)*1000
    local loadFrames,loadSamples,loadAudit=0,{},0;local loadingStart=timer()
    while not renderer:terrainReady() do
        pump();loadFrames=loadFrames+1
        local before=timer();if imageLoader then imageLoader.update() end
        renderer:prepare(camera,1/60);local stats=terrainStats(renderer)
        loadingText(stats);local pixels
        if loadFrames==1 or renderer:terrainReady() then love.graphics.captureScreenshot(function(data)pixels=data end) end
        love.graphics.present();loadSamples[#loadSamples+1]=(timer()-before)*1000
        if pixels then
            local encoding=timer();saveImage(output,renderer:terrainReady() and 'loading-complete' or 'loading-first-step',pixels)
            loadAudit=loadAudit+(timer()-encoding)
        end
        if loadFrames%120==0 then print('TERRAIN LOADING '..loadFrames..' tiles='..tostring(stats.completed)..'/'..tostring(stats.total));io.flush() end
        assert(timer()-loadingStart<150 and loadFrames<18000,'Terrain preload did not complete within bounded test window')
    end
    local initial=terrainStats(renderer);local initialGroundAllocations=groundAllocations
    report.startup.ground_mesh_allocations=initialGroundAllocations
    report.loading={frames=loadFrames,elapsed_ms=(timer()-loadingStart-loadAudit)*1000,
        frame_ms=#loadSamples>0 and summary(loadSamples) or nil,terrain=initial}
    local TerrainCache=require('src.commute.terrain_cache')
    local cacheComplete=TerrainCache.available(renderer.terrainStore)
    local cacheTile=renderer.terrain.tiles[1]
    local cachedTile,cacheReason
    if cacheComplete then cachedTile,cacheReason=TerrainCache.readTile(renderer.terrainStore,cacheTile,true)
    else cacheReason='cache_incomplete' end
    report.terrain_cache={complete=cacheComplete,writable=renderer.terrainCacheWritable==true,
        warm_load_used=renderer.terrainCacheReady==true,
        directory=renderer.terrainStore and renderer.terrainStore.directory,
        estimated_full_path_length=#love.filesystem.getSaveDirectory()+1+#(renderer.terrainStore and renderer.terrainStore.directory or ''),
        write_failure=renderer.terrainCacheFailure,
        sample_tile=cacheTile and cacheTile.key,sample_read=cachedTile~=nil,sample_reason=cacheReason,
        sample_vertices=cachedTile and cachedTile.vertexCount,sample_indices=cachedTile and cachedTile.indexCount}
    initial.resident=residentCount(initial);initial.culled=culledCount(initial)
    check('loading_reaches_complete_world',initial.ready~=false and initial.completed==initial.total and initial.total>0
        and initial.resident==initial.total and initial.submitted<=initial.resident
        and initial.vertices>0 and initial.meshBytes>0 and initial.uncovered==0,initial)
    write()
    local longest,longestId
    for id in pairs(world.roads.destinations) do if id~='warehouse' then
        local route=Routes:find('warehouse',id)
        if route and (not longest or route.length>longest.length) then longest,longestId=route,id end
    end end
    assert(longest,'No continuous road route available')
    local reverse=assert(Routes:find(longestId,'warehouse'))
    report.route={destination=longestId,length=longest.length,speed_mps=26.8,wraps=false}
    local bridge
    for _,p in ipairs(renderer.structures and renderer.structures.pieces or {}) do
        if p.kind=='bridgeDeck' and (not bridge or (p.radius or 0)>(bridge.radius or 0)) then bridge=p end
    end
    bridge=bridge or world.roads.destinations[longestId]
    local function place(x,z,heading,firstPerson)
        actor.x,actor.z,actor.heading,actor.speed=x,z,heading or 0,0
        actor.h=world:supportHeight(x,z);actor.pitch,actor.grade,actor.lean=0,0,0
        camera=Camera.new(actor,world);camera.zoom=.8;camera.targetZoom=.8
        if firstPerson then camera:setFirstPerson(true,actor) end
    end
    local function follow(route,distance)
        local remaining=math.min(distance,route.length-.001)
        for index=2,#route.points do
            local a,b=route.points[index-1],route.points[index]
            local dx,dz=b.x-a.x,b.z-a.z;local length=math.sqrt(dx*dx+dz*dz)
            if remaining<=length then
                local t=remaining/length;actor.x,actor.z=a.x+dx*t,a.z+dz*t
                actor.heading=math.atan2(dz,dx);actor.speed=26.8;actor.distance=distance
                actor.h=world:supportHeight(actor.x,actor.z)
                local h1=world:supportHeight(actor.x+math.cos(actor.heading)*.25,actor.z+math.sin(actor.heading)*.25)
                local h0=world:supportHeight(actor.x-math.cos(actor.heading)*.25,actor.z-math.sin(actor.heading)*.25)
                actor.grade=(h1-h0)*2;actor.pitch=math.atan(actor.grade)
                return
            end
            remaining=remaining-length
        end
    end
    local componentProfile={stage=nil,samples={},current=nil}
    local function pack(...) return {n=select('#',...),...} end
    local function instrument(target,key,name)
        local original=target and target[key]
        if type(original)~='function' then return end
        target[key]=function(...)
            local started=timer();local values=pack(original(...));local elapsed=(timer()-started)*1000
            local stageName=componentProfile.stage
            if stageName then
                local stage=componentProfile.samples[stageName]
                local samples=stage[name]
                if not samples then samples={};stage[name]=samples end
                samples[#samples+1]=elapsed
                if componentProfile.current then
                    componentProfile.current[name]=(componentProfile.current[name] or 0)+elapsed
                end
            end
            return unpack(values,1,values.n)
        end
    end
    instrument(renderer,'prepareTerrain','terrain_prepare')
    instrument(renderer,'coverageRadius','coverage_radius')
    instrument(renderer,'updateTerrainDrawList','terrain_draw_list')
    instrument(renderer,'props','props_total')
    instrument(renderer.grassFields,'collect','grass_collect')
    instrument(renderer.plantMotion,'update','plant_motion')
    instrument(renderer.plantSprites,'prepare','plant_prepare')
    instrument(renderer.vegetation,'visible','vegetation_visible')
    instrument(renderer,'drawGrass','draw_grass')
    instrument(renderer,'drawTerrain','draw_terrain_submit')
    instrument(renderer,'drawRoads','draw_roads')
    instrument(renderer,'drawOutsideActor','draw_actor')
    instrument(renderer,'headlight','draw_headlight')
    instrument(renderer.structures,'drawOutsideDepth','draw_structures_depth')
    instrument(renderer.structures,'drawOutsidePropsDepth','draw_structures_props')
    instrument(renderer.structures,'drawFirstPerson','draw_structures_first_person')
    instrument(renderer.plantSprites,'drawPlant','draw_plant_sprites')
    local function stage(name,count,update)
        collectgarbage('collect')
        local samples,captures={},{};local auditSeconds=0
        componentProfile.stage=name;componentProfile.samples[name]={}
        local stageStart=timer()
        for index=1,count do
            pump();local before=timer()
            if imageLoader then imageLoader.update() end
            Rider.update(rider,{},1/60,world)
            if update then update(index) else actor.speed=0 end
            camera:updateRide(rider,1/60)
            local updateMs=(timer()-before)*1000
            componentProfile.current={}
            local t=timer();renderer:prepare(camera,1/60);local prepareMs=(timer()-t)*1000
            local prepareComponents=componentProfile.current;componentProfile.current=nil
            local stats=terrainStats(renderer)
            local resident=residentCount(stats)
            local submitted=stats.submitted or resident
            local culled=culledCount(stats)
            local plantPrepareRan=prepareComponents.plant_prepare~=nil
            local row={index=index,update_ms=updateMs,prepare_ms=prepareMs,pending=renderer.pending or 0,
                ready=renderer:terrainReady(),uncovered=stats.uncovered,completed=stats.completed,total=stats.total,
                resident=resident,submitted=submitted,culled=culled,
                vertices=stats.vertices,mesh_bytes=stats.meshBytes,terrain_mesh_allocations=groundAllocations-initialGroundAllocations,
                actor_x=actor.x,actor_z=actor.z,
                camera_x=camera.centerX,camera_z=camera.centerZ,zoom=camera.zoom,first_person=camera.firstPerson==true}
            row.prepare_components_ms=prepareComponents
            row.plant_prepare_internal_ms=plantPrepareRan and (renderer.plantSprites.lastPrepareMs or 0) or 0
            row.plant_upload_ms=plantPrepareRan and (renderer.plantSprites.lastUploadMs or 0) or 0
            row.plant_upload_bytes=plantPrepareRan and (renderer.plantSprites.lastPrepareBytes or 0) or 0
            row.plant_page_bytes=renderer.plantSprites.bytes or 0
            row.plant_motion_bytes=renderer.plantSprites.motionBytes or 0
            row.visible_props=#(renderer.visibleProps or {})
            local grassStats=renderer.grassFields and renderer.grassFields:stats() or {}
            local vegetationStats=renderer.vegetation and renderer.vegetation:stats() or {}
            row.grass_visible=grassStats.visible or 0
            row.grass_build_ms=grassStats.buildMs or 0
            row.grass_mesh_bytes=grassStats.meshBytes or 0
            row.grass_pending=grassStats.pending and 1 or 0
            row.grass_built=grassStats.built or 0
            row.grass_steps=grassStats.steps or 0
            row.vegetation_pending=vegetationStats.pending or 0
            row.vegetation_cached_patches=vegetationStats.patches or 0
            row.vegetation_generated=vegetationStats.generated or 0
            row.vegetation_builds=vegetationStats.built or 0
            row.vegetation_job=renderer.vegetation and renderer.vegetation._visibleJob and 1 or 0
            check(name..':ground_ready:'..index,row.ready and row.uncovered==0 and row.completed==row.total
                and row.resident==row.total and row.submitted<=row.resident
                and row.culled==row.resident-row.submitted,row)
            check(name..':resident_mesh_stable:'..index,stats.total==initial.total and stats.completed==initial.completed
                and stats.vertices==initial.vertices and stats.meshBytes==initial.meshBytes and row.terrain_mesh_allocations==0,row)
            t=timer();love.graphics.setCanvas();love.graphics.origin()
            componentProfile.current={}
            renderer:draw(camera,actor,{{actor=actor,bikeOnly=false}})
            cockpit:draw(actor,rider.gear.engine,1280,880,nil,camera)
            love.graphics.flushBatch();row.draw_ms=(timer()-t)*1000
            row.draw_components_ms=componentProfile.current;componentProfile.current=nil
            local graphics=love.graphics.getStats();row.draw_calls=graphics.drawcalls;row.texture_bytes=graphics.texturememory
            local capture=index==1 or index==8 or index==60 or index==count
            if capture then
                love.graphics.captureScreenshot(function(data)captures[#captures+1]={index=index,data=data} end)
            end
            t=timer();love.graphics.present();row.present_ms=(timer()-t)*1000
            row.frame_ms=(timer()-before)*1000;row.gpu_readback=capture
            if capture then
                local auditStart=timer();local points=Audit.samples(camera,world);local missing={}
                for _,p in ipairs(points) do
                    if drawCoverage(renderer,p.x,p.z)~=true then missing[#missing+1]=p end
                end
                row.coverage_rays=#points;row.uncovered_rays=#missing
                row.coverage_audit_ms=(timer()-auditStart)*1000;auditSeconds=auditSeconds+row.coverage_audit_ms/1000
                check(name..':viewport_ground_rays:'..index,#points>0 and #missing==0,{tested=#points,missing=missing})
            end
            samples[#samples+1]=row
            if index==1 or index==count then print(string.format('COVERAGE %s frame%d %.2fms ready=%s missing=%s rays=%s',
                name,index,row.frame_ms,tostring(row.ready),tostring(row.uncovered),tostring(row.uncovered_rays)));io.flush() end
        end
        local elapsed=timer()-stageStart
        local row={name=name,frames=count,metrics={},elapsed_ms=elapsed*1000,audit_ms=auditSeconds*1000,
            gpu_drained_adjusted_fps=count/(elapsed-auditSeconds),over_16_67ms=0}
        for _,key in ipairs({'frame_ms','update_ms','prepare_ms','draw_ms','present_ms','draw_calls','texture_bytes','pending'}) do
            local values={};for _,sample in ipairs(samples) do values[#values+1]=sample[key] end
            row.metrics[key]=summary(values)
        end
        for _,sample in ipairs(samples) do if sample.frame_ms>1000/60 then row.over_16_67ms=row.over_16_67ms+1 end end
        row.prepare_components_ms={}
        for component,values in pairs(componentProfile.samples[name]) do
            row.prepare_components_ms[component]=summary(values)
        end
        local drawComponents={}
        for _,sample in ipairs(samples) do
            for component,value in pairs(sample.draw_components_ms or {}) do
                drawComponents[component]=drawComponents[component] or {}
                drawComponents[component][#drawComponents[component]+1]=value
            end
        end
        row.draw_components_ms={}
        for component,values in pairs(drawComponents) do row.draw_components_ms[component]=summary(values) end
        componentProfile.stage=nil
        row.frame_budget_pass=row.metrics.frame_ms.p95<=1000/60
        report.rows[#report.rows+1]=row;report.samples[name]=samples
        for _,capture in ipairs(captures) do saveImage(output,name..'-frame-'..capture.index,capture.data) end
        print(string.format('COVERAGE COMPLETE %s p95=%.2fms max=%.2fms adjusted-fps=%.1f',
            name,row.metrics.frame_ms.p95,row.metrics.frame_ms.max,row.gpu_drained_adjusted_fps));io.flush();write()
    end
    stage('outside_first_visible',90)
    place(bridge.x,bridge.z,0,false);stage('outside_cold_jump',90)
    camera.zoom=Camera.ZOOM_MIN;camera.targetZoom=Camera.ZOOM_MIN;camera.tilt=Camera.TILT_MIN
    stage('outside_max_zoom_low_tilt',120)
    stage('outside_orbit',180,function(i)camera.yaw=i*2;camera.tilt=20+32.5*(1-math.cos(i/180*math.pi*2)) end)
    follow(reverse,0);camera=Camera.new(actor,world);camera.zoom=.55;camera.targetZoom=.55
    stage('outside_fast_ride',360,function(i)follow(reverse,i*26.8/60)end)
    place(bridge.x,bridge.z,math.pi*.25,true);stage('first_person_cold_jump',90)
    camera.fov=100;FP.update(camera,actor,0);stage('first_person_wide_lens',120)
    stage('first_person_orbit',240,function(i)camera.lookYaw=-math.pi+i*math.pi*2/240;camera.lookPitch=math.sin(i/240*math.pi*2)*.14 end)
    follow(longest,0);camera=Camera.new(actor,world);camera:setFirstPerson(true,actor);camera.fov=100
    stage('first_person_fast_ride',360,function(i)follow(longest,i*26.8/60)end)
    place(origin.x,origin.z,0,false);stage('outside_revisit',180)
    report.complete=true;report.pass=(report.failed_checks or 0)==0
    report.performance_pass=true
    for _,row in ipairs(report.rows) do if not row.frame_budget_pass then report.performance_pass=false end end
    report.final_terrain=terrainStats(renderer);write();renderer:release();love.graphics.newMesh=originalNewMesh
    if imageLoader then imageLoader.shutdown();imageLoader.setEnabled(false) end
    love.event.quit(report.pass and report.performance_pass and 0 or 1)
end
return Probe
