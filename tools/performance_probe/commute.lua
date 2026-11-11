-- Standalone real-engine motorcycle benchmark. Uses only a private test identity.
local P={}
function P.install()
    local snapshot=os.getenv('PICTURE_SHOP_COMMUTE_BASELINE_SOURCE')
    if snapshot and snapshot~='' then
        table.insert(package.loaders,1,function(name)
            if name:match('^src%.commute%.') then
                local path=snapshot..'/'..name:gsub('%.','/')..'.lua'
                local chunk,reason=loadfile(path)
                return chunk or ('\n'..tostring(reason))
            end
        end)
    end
    function love.errorhandler(message)
        io.stderr:write(tostring(message)..'\n'..debug.traceback()..'\n');io.stderr:flush()
        return function() return 1 end
    end
    function love.load()
        local output=assert(os.getenv('PICTURE_SHOP_PERFORMANCE_OUTPUT'))
        local identity=assert(os.getenv('PICTURE_SHOP_TEST_IDENTITY'))
        assert(identity:match('^the%-picture%-shop%-test%-[%w%-]+$'))
        love.filesystem.setIdentity(identity)
        love.window.setMode(1280,880,{resizable=false,vsync=0})
        love.window.setTitle('Motorcycle performance probe')
        if os.getenv('PICTURE_SHOP_PERFORMANCE_TERRAIN_COVERAGE')=='1' then
            return require('tools.performance_probe.terrain_coverage').run(output,identity)
        end
        local timer=love.timer.getTime
        local report={scenario='motorcycle',width=1280,height=880,vsync=0,identity=identity,
            source=snapshot or 'working tree',rows={},startup={},samples={}}
        local gpu,version,vendor,device=love.graphics.getRendererInfo()
        report.graphics={name=gpu,version=version,vendor=vendor,device=device,os=love.system.getOS()}
        local function writeReport()
            local file=assert(io.open(output..'/measurements.json','wb'))
            file:write(require('tools.performance_probe.json')(report));file:close()
        end
        local gpuFence=os.getenv('PICTURE_SHOP_PERFORMANCE_GPU_FENCE')=='1'
        local bridgeStress=os.getenv('PICTURE_SHOP_PERFORMANCE_BRIDGE_STRESS')=='1'
        report.timing_note=gpuFence and 'Window draw/present percentiles; every stage ends with screenshot GPU readback. Series throughput includes all stage wall time through that fence; no limiter.'
            or 'CPU/update/draw/present wall time; GPU work may queue, no per-stage fence.'
        local frame
        local function instrument(target,key,name)
            local original=target[key]
            if not original then return end
            target[key]=function(...)
                local start=timer();local values={original(...)};local ms=(timer()-start)*1000
                local dest=frame or report.startup
                dest[name..'_ms']=(dest[name..'_ms'] or 0)+ms
                dest[name..'_calls']=(dest[name..'_calls'] or 0)+1
                if name=='plant_prepare' and frame then frame.plant_ready=values[2]==true end
                return unpack(values)
            end
        end
        local start=timer()
        local Terrain=require('src.commute.terrain')
        local Roads=require('src.commute.roads')
        local Rider=require('src.commute.rider')
        local Camera=require('src.commute.camera')
        local Renderer=require('src.commute.renderer')
        local PlantSprites=require('src.commute.vendor.plant_sprites')
        local BikeActionPages=require('src.commute.bike_action_pages')
        local Flora=require('src.commute.flora')
        local PlantMotion=require('src.commute.vendor.plant_motion')
        local FirstPersonCamera=require('src.commute.first_person_camera')
        local ImageLoader=require('src.image_loader')
        report.startup.modules_ms=(timer()-start)*1000
        instrument(Renderer,'build','terrain_build')
        instrument(require('src.commute.shadows'),'draw','shadow_draw')
        instrument(require('src.commute.truck_turntable_pages'),'get','truck_texture')
        instrument(Renderer,'buildStep','terrain_build')
        instrument(Renderer,'props','props')
        instrument(Renderer,'buildRoadMeshes','road_meshes')
        instrument(require('src.commute.vegetation'),'visible','vegetation_visible')
        instrument(PlantSprites,'prepare','plant_prepare')
        instrument(PlantSprites,'_visibleKeys','plant_visible_keys')
        instrument(PlantSprites,'_pageOrder','plant_page_order')
        instrument(PlantSprites,'_protectedPages','plant_protected_pages')
        instrument(PlantSprites,'_updateDemand','plant_demand')
        instrument(PlantSprites,'_trimToBudget','plant_cache_trim')
        instrument(PlantSprites,'_loadPage','plant_page_load')
        instrument(PlantSprites,'_loadImage','plant_image_load')
        instrument(BikeActionPages,'get','bike_action_page')
        instrument(BikeActionPages,'prepare','bike_action_prepare')
        instrument(ImageLoader,'update','image_loader_update')
        for _,name in ipairs({'ground_textures','vegetation','bike_art','warehouse_art','bridge_art','structures'}) do
            instrument(require('src.commute.'..name),'new',name..'_new')
        end
        instrument(require('src.commute.ground_textures'),'prepare','ground_prepare')
        instrument(require('src.commute.structures'),'drawOutside','structure_draw')
        instrument(require('src.commute.structures'),'drawFirstPerson','structure_draw')
        start=timer();local roads,world
        local townSeedText=os.getenv('PICTURE_SHOP_TOWN_SEED')
        local townSeed=townSeedText and townSeedText~='' and assert(tonumber(townSeedText),'Town seed must be numeric') or nil
        if townSeed then
            local Town=require('src.commute.town')
            local Truck=require('src.commute.delivery_truck')
            local blocked=Truck.blocked;local clearanceChecks=0
            Truck.blocked=function(...)
                clearanceChecks=clearanceChecks+1
                return blocked(...)
            end
            local townProfiler=os.getenv('PICTURE_SHOP_PERFORMANCE_PROFILE')=='1' and require('jit.profile')
            local townStacks={}
            if townProfiler then townProfiler.start('i1',function(thread,count)
                local stack=townProfiler.dumpstack(thread,'pl\n',12)
                townStacks[stack]=(townStacks[stack] or 0)+count
            end) end
            local generationStarted=timer()
            local generated,reason=Town.generate(townSeed)
            report.startup.town_generation_ms=(timer()-generationStarted)*1000
            Truck.blocked=blocked
            report.startup.truck_clearance_checks=clearanceChecks
            if townProfiler then
                townProfiler.stop();report.startup.town_generation_profile={}
                for stack,count in pairs(townStacks) do
                    report.startup.town_generation_profile[#report.startup.town_generation_profile+1]={stack=stack,samples=count}
                end
                table.sort(report.startup.town_generation_profile,function(a,b)return a.samples>b.samples end)
            end
            assert(generated,reason)
            world=Town.world(generated);roads=world.roads
            report.town={seed=townSeed,id=world.townId,generator_version=generated.generatorVersion,
                buildings=#roads.sites.all,road_segments=#roads.segments}
        else roads=Roads.new();world=roads:attach(Terrain.new()) end
        report.startup.world_ms=(timer()-start)*1000
        local forceMobile=os.getenv('PICTURE_SHOP_TERRAIN_FORCE_MOBILE')=='1'
        local rendererOptions={mobile=forceMobile}
        local foliageRadius=tonumber(os.getenv('PICTURE_SHOP_MOBILE_FOLIAGE_RADIUS'))
        if foliageRadius then
            assert(forceMobile and foliageRadius>0,'Mobile foliage radius override requires the forced-mobile policy')
            Renderer.MOBILE_FOLIAGE_RADIUS=foliageRadius
        end
        ImageLoader.setEnabled(true)
        start=timer();local renderer=Renderer.new(world,nil,rendererOptions)
        local shadowHour=tonumber(os.getenv('PICTURE_SHOP_SHADOW_HOUR'))
        if shadowHour then
            require('src.video_settings').apply({vegetationShadows=os.getenv('PICTURE_SHOP_SHADOW_TREES')=='1',
                shadowDistance=os.getenv('PICTURE_SHOP_SHADOW_DISTANCE') or 'medium',
                renderDistance=os.getenv('PICTURE_SHOP_RENDER_DISTANCE') or 'medium'})
            renderer.calendar={month=6,day=1,totalDays=0,elapsed=shadowHour/24*1200,secondsPerDay=1200}
            renderer.shadows.disabled=os.getenv('PICTURE_SHOP_SHADOWS_OFF')=='1'
            report.shadow_hour=shadowHour;report.shadows_enabled=not renderer.shadows.disabled
            report.video_settings=require('src.video_settings').current
        end
        report.startup.renderer_ms=(timer()-start)*1000
        report.mobile_policy=renderer.mobile==true
        report.mobile_foliage_radius=Renderer.MOBILE_FOLIAGE_RADIUS
        report.async_images=true
        report.async_bike_action_pages=ImageLoader.enabled
        report.plant_sprite_base_budget_bytes=renderer.plantSprites.baseBudget
        report.ground_atlas={mobile=renderer.ground.mobile,path=renderer.ground.atlasPath,
            bytes=renderer.ground.bytes,width=renderer.ground.size}
        if renderer.structures then
            report.structures={pieces=#renderer.structures.pieces,buildings=#renderer.structures.buildings,vertices=0,bridges=0,bridge_pieces=0}
            for _,p in ipairs(renderer.structures.pieces) do
                report.structures.vertices=report.structures.vertices+(p.vertexCount or 0)
                if p.kind=='bridgeDeck' then report.structures.bridges=report.structures.bridges+1 end
                if p.kind~='building' then report.structures.bridge_pieces=report.structures.bridge_pieces+1 end
            end
        end
        start=timer();local cockpit=require('src.commute.cockpit').new()
        report.startup.cockpit_ms=(timer()-start)*1000
        start=timer();renderer:prewarmViews()
        report.startup.view_prewarm_ms=(timer()-start)*1000
        start=timer();cockpit:prewarmFirstPerson();require('src.commute.ui_icons').prewarm()
        report.startup.first_person_prewarm_ms=(timer()-start)*1000
        local route=assert(require('src.commute.routes').new(roads):find('warehouse','brick-walkup'))
        local spawn=roads.destinations.warehouse
        local heading=townSeed and math.atan2(route.points[2].z-spawn.z,route.points[2].x-spawn.x) or -.7
        local rider=Rider.new(spawn.x,spawn.z,heading,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
        Rider.update(rider,{},0,world)
        local actor=rider.bike
        local nightScenario=os.getenv('PICTURE_SHOP_NIGHT_SCENARIO')
        if nightScenario=='truck' then
            actor=require('src.commute.delivery_truck').new(spawn.x,spawn.z,heading)
            actor.h=world:supportHeight(actor.x,actor.z);actor.headlight=true
        elseif nightScenario=='lamp' then
            for _,f in ipairs(require('src.commute.infrastructure').ensure(world).fixtures) do
                if f.kind=='lamp' then actor.x=f.x+1.5;actor.z=f.z+1.5;break end
            end
            actor.h=world:supportHeight(actor.x,actor.z);actor.headlight=false
        end
        local sceneActors={{actor=actor,truck=nightScenario=='truck',bikeOnly=false,localPlayer=true}}
        local camera=Camera.new(actor,world)
        report.night_scenario=nightScenario
        local paintId=os.getenv('PICTURE_SHOP_BIKE_PAINT')
        if paintId and paintId~='' then
            assert(require('src.commute.bike_paint').valid(paintId),'Unknown benchmark paint finish')
            actor.paintId=paintId
        end
        report.paintId=actor.paintId or 'bronze'
        camera.zoom=.8;camera.targetZoom=.8;camera.yaw=20
        report.route={length=route.length,points=#route.points}
        local function position(distance)
            local remaining=distance%route.length
            for i=2,#route.points do
                local a,b=route.points[i-1],route.points[i]
                local dx,dz=b.x-a.x,b.z-a.z;local length=math.sqrt(dx*dx+dz*dz)
                if remaining<=length then
                    local blend=remaining/length
                    actor.x=a.x+dx*blend;actor.z=a.z+dz*blend
                    actor.heading=math.atan2(dz,dx);actor.speed=18;actor.distance=distance
                    actor.h=world:supportHeight(actor.x,actor.z);return
                end
                remaining=remaining-length
            end
        end
        local function stats(values)
            table.sort(values);local sum=0
            for _,value in ipairs(values) do sum=sum+value end
            return {mean=sum/#values,p50=values[math.ceil(#values*.5)],p95=values[math.ceil(#values*.95)],
                p99=values[math.ceil(#values*.99)],max=values[#values]}
        end
        local captures=os.getenv('PICTURE_SHOP_PERFORMANCE_CAPTURES')=='1'
        local captureOnly=os.getenv('PICTURE_SHOP_PERFORMANCE_CAPTURE_ONLY')=='1'
        local function capture(name)
            if not captures then return end
            love.graphics.origin();renderer:draw(camera,actor,sceneActors)
            cockpit:draw(actor,rider.gear.engine,1280,880,nil,camera)
            love.graphics.captureScreenshot(function(data)
                local encoded=data:encode('png');local file=assert(io.open(output..'/'..name..'.png','wb'))
                file:write(encoded:getString());file:close();encoded:release();data:release()
            end)
            love.graphics.present()
        end
        local profiler=os.getenv('PICTURE_SHOP_PERFORMANCE_PROFILE')=='1' and require('jit.profile')
        local function stage(name,count,update,untilReady)
            collectgarbage('collect')
            local samples={};local stacks={};local readyAt;local fencedPixels
            local heldX,heldZ=actor.x,actor.z
            if profiler then profiler.start('i1',function(thread,n)
                local stack=profiler.dumpstack(thread,'pl\n',12);stacks[stack]=(stacks[stack] or 0)+n
            end) end
            local stageStarted=timer()
            for index=1,count do
                love.event.pump()
                for event,a in love.event.poll() do if event=='quit' then error('Probe interrupted: '..tostring(a)) end end
                frame={index=index};local began=timer()
                local t=timer();ImageLoader.update();Rider.update(rider,{},1/60,world)
                if not name:find('streaming',1,true) then actor.x,actor.z,actor.speed=heldX,heldZ,0 end
                if update then update(index) end
                camera:updateRide(rider,1/60)
                frame.update_ms=(timer()-t)*1000
                t=timer();renderer:prepare(camera,1/60);frame.prepare_ms=(timer()-t)*1000
                t=timer();love.graphics.origin();love.graphics.clear(.03,.04,.04,1)
                renderer:draw(camera,actor,sceneActors)
                cockpit:draw(actor,rider.gear.engine,1280,880,nil,camera)
                love.graphics.flushBatch();frame.draw_ms=(timer()-t)*1000
                local graphics=love.graphics.getStats()
                frame.draw_calls=graphics.drawcalls;frame.texture_bytes=graphics.texturememory
                local ready=false
                if untilReady and index>=60 and index%6==0 then
                    local visiblePagesReady=renderer.plantSprites:readyFor(
                        renderer.visibleProps,renderer.calendar,renderer.clock)
                    local imageQueueIdle=not ImageLoader.pending()
                    ready=(renderer.pending or 0)==0 and renderer.vegetation:stats().pending==0
                        and visiblePagesReady and imageQueueIdle
                end
                local finalFrame=index==count or (untilReady and ready)
                if gpuFence and finalFrame then
                    love.graphics.captureScreenshot(function(data) fencedPixels=data end)
                end
                t=timer();love.graphics.present();frame.present_ms=(timer()-t)*1000
                frame.frame_ms=(timer()-began)*1000
                frame.pending=renderer.pending or 0;frame.visible_chunks=#(renderer.visible or {})
                frame.terrain_resident_tiles=frame.visible_chunks
                frame.terrain_submitted_tiles=#(renderer.drawTiles or renderer.visible or {})
                frame.terrain_build_ms=renderer.buildMs or 0
                local grass=renderer.grassFields
                frame.grass_collect_ms=grass and grass.buildMs or 0
                frame.grass_builds=grass and grass.buildsThisFrame or 0
                frame.grass_steps=grass and grass.stepsThisFrame or 0
                frame.grass_visible_patches=grass and grass.visibleCount or 0
                frame.grass_mesh_bytes=grass and grass.meshBytes or 0
                frame.visible_props=#(renderer.visibleProps or {})
                frame.visible_canopy_props,frame.visible_brush_props=0,0
                for _,prop in ipairs(renderer.visibleProps or {}) do
                    if Flora.canopy[prop.kind] then
                        frame.visible_canopy_props=frame.visible_canopy_props+1
                    else
                        frame.visible_brush_props=frame.visible_brush_props+1
                    end
                end
                frame.outdoor_props_fully_offscreen=0
                frame.outdoor_plant_page_runs=0
                frame.first_person_props_fully_offscreen=0
                local view=camera.shoulderView or camera
                if not view.firstPerson then
                    local width,height=renderer.viewportWidth or 1280,renderer.viewportHeight or 880
                    local previousPage
                    local sprites=renderer.plantSprites
                    for _,prop in ipairs(renderer.visibleProps or {}) do
                        local x,y=view:screen(prop.x,prop.z,prop.h)
                        local size=prop.scale*view.zoom
                        local halfWidth=(128+256*PlantMotion.MAX_SWAY)*size+2
                        local offscreen=x+halfWidth<0 or x-halfWidth>width
                            or y+8*size<0 or y-248*size>height
                        if offscreen then
                            frame.outdoor_props_fully_offscreen=frame.outdoor_props_fully_offscreen+1
                        end
                        if not offscreen then
                            local key=sprites:plantKey(prop,renderer.calendar,renderer.clock)
                            local entry=key and sprites.layout.entries[key]
                            local page=entry and entry[1]
                            if page and sprites.pageImages[page] then
                                if page~=previousPage then
                                    frame.outdoor_plant_page_runs=frame.outdoor_plant_page_runs+1
                                    previousPage=page
                                end
                            end
                        end
                    end
                else
                    local width,height=view.viewportWidth or 1280,view.viewportHeight or 880
                    local radius=renderer.visiblePropsRadius or renderer.effectiveRadius
                    local cosine,sine=math.cos(view.roll or 0),math.sin(view.roll or 0)
                    for _,prop in ipairs(renderer.visibleProps or {}) do
                        local sx,sy,depth=view:screen(prop.x,prop.z,prop.h)
                        local dx,dz=prop.x-view.centerX,prop.z-view.centerZ
                        local distance=math.sqrt(dx*dx+dz*dz)
                        local cameraScale=view.focal/depth/48
                        if depth>=FirstPersonCamera.NEAR and depth<=FirstPersonCamera.FAR
                            and distance<radius
                            and sx>=-width*.5*cameraScale and sx<=width+width*.5*cameraScale then
                            local size=prop.scale*cameraScale
                            local halfX=(128+256*PlantMotion.MAX_SWAY)*size
                            local halfY=128*size
                            local centerY=-120*size
                            local centerX=-sine*centerY
                            centerY=centerY*cosine
                            local boundX=math.abs(cosine)*halfX+math.abs(sine)*halfY+2
                            local boundY=math.abs(sine)*halfX+math.abs(cosine)*halfY+2
                            if sx+centerX+boundX<0 or sx+centerX-boundX>width
                                or sy+centerY+boundY<0 or sy+centerY-boundY>height then
                                frame.first_person_props_fully_offscreen=frame.first_person_props_fully_offscreen+1
                            end
                        end
                    end
                end
                frame.radius=renderer.effectiveRadius or 0
                frame.vegetation_pending=renderer.vegetation:stats().pending or 0
                frame.plant_upload_bytes=renderer.plantSprites.lastPrepareBytes or 0
                frame.plant_motion_bytes=renderer.plantSprites.motionBytes or 0
                frame.plant_pages_wanted=renderer.plantSprites.wantedPageCount or 0
                frame.plant_pages_pending=renderer.plantSprites.pendingPageCount or 0
                frame.plant_pages_resident=0
                for _ in pairs(renderer.plantSprites.pageImages or {}) do frame.plant_pages_resident=frame.plant_pages_resident+1 end
                frame.plant_sprite_bytes=renderer.plantSprites.bytes or 0
                frame.plant_sprite_effective_budget_bytes=renderer.plantSprites.effectiveBudget or 0
                frame.image_loader_pending=ImageLoader.pending() and 1 or 0
                frame.image_loader_ready_bytes=ImageLoader.readyBytes()
                frame.bike_action_pages_resident=renderer.bikeArt.actionPages.count or 0
                frame.bike_action_pages_pending=renderer.bikeArt.actionPages.pendingCount or 0
                frame.actor_x,frame.actor_z,frame.actor_speed=actor.x,actor.z,actor.speed
                frame.camera_x,frame.camera_z=camera.centerX,camera.centerZ
                samples[#samples+1]=frame
                if ready and not readyAt then readyAt=index end
                if index<=3 or index%60==0 then
                    print(('%s %d frame=%.2fms prep=%.2fms vegetation=%.2fms terrain=%.2fms draw=%.2fms present=%.2fms pending=%d plants=%d/%d resident pages (%d pending), bike=%d/%d pages, loader=%d'):format(
                        name,index,frame.frame_ms,frame.prepare_ms,frame.vegetation_visible_ms or 0,frame.terrain_build_ms or 0,
                        frame.draw_ms,frame.present_ms,frame.pending,frame.plant_pages_resident,frame.plant_pages_wanted,
                        frame.plant_pages_pending,frame.bike_action_pages_resident,frame.bike_action_pages_pending,
                        frame.image_loader_pending));io.flush()
                end
                frame=nil
                if index==1 then capture(name..'-first') end
                if untilReady and ready and index>=60 then break end
            end
            local stageElapsed=timer()-stageStarted
            if profiler then profiler.stop() end
            assert(not gpuFence or fencedPixels,'Stage GPU readback did not complete: '..name)
            if untilReady and not readyAt then
                report.failed_stage=name
                report.plant_settle_debug={visible_props=#(renderer.visibleProps or {}),
                    wanted_pages=renderer.plantSprites.wantedPageCount or 0,
                    pending_pages=renderer.plantSprites.pendingPageCount or 0,
                    resident_pages=0,image_loader_pending=ImageLoader.pending(),
                    image_loader_ready_bytes=ImageLoader.readyBytes(),
                    last_prepare_ready=samples[#samples].plant_ready,
                    wanted_motion=0,missing_motion=0,resident_motion=0}
                for _ in pairs(renderer.plantSprites.pageImages or {}) do
                    report.plant_settle_debug.resident_pages=report.plant_settle_debug.resident_pages+1
                end
                for key in pairs(renderer.plantSprites.wanted or {}) do
                    report.plant_settle_debug.wanted_motion=report.plant_settle_debug.wanted_motion+1
                    if not renderer.plantSprites.motion[key] then
                        report.plant_settle_debug.missing_motion=report.plant_settle_debug.missing_motion+1
                    end
                end
                for _ in pairs(renderer.plantSprites.motion or {}) do
                    report.plant_settle_debug.resident_motion=report.plant_settle_debug.resident_motion+1
                end
                writeReport()
            end
            assert(not untilReady or readyAt, 'Scenery did not settle during '..name)
            local row={name=name,frames=#samples,ready_frame=readyAt or -1,first_frame_ms=samples[1].frame_ms,
                final_pending=samples[#samples].pending,final_vegetation_pending=samples[#samples].vegetation_pending,metrics={},profile={}}
            for key,value in pairs(samples[1]) do
                if type(value)=='number' and key~='index' then
                    local values={};for _,sample in ipairs(samples) do values[#values+1]=sample[key] or 0 end
                    row.metrics[key]=stats(values)
                end
            end
            -- Include stage counters that did not occur in the first frame.
            for _,sample in ipairs(samples) do for key,value in pairs(sample) do
                if key~='index' and type(value)=='number' and not row.metrics[key] then
                    local values={};for _,entry in ipairs(samples) do values[#values+1]=entry[key] or 0 end
                    row.metrics[key]=stats(values)
                end
            end end
            for stack,n in pairs(stacks) do row.profile[#row.profile+1]={stack=stack,samples=n} end
            table.sort(row.profile,function(a,b) return a.samples>b.samples end)
            while #row.profile>30 do table.remove(row.profile) end
            local sum=0;for _,sample in ipairs(samples) do sum=sum+sample.frame_ms end
            row.throughput_fps=1000/(sum/#samples)
            row.elapsed_ms=stageElapsed*1000
            row.gpu_drained_series_fps=gpuFence and #samples/stageElapsed or nil
            row.final_gpu_readback=gpuFence
            if shadowHour and (name=='stationary' or name=='first_person_steady') then
                local pixels=renderer:prewarmViews().canvas:newImageData()
                local file=assert(io.open(output..'/'..name..'.png','wb'));file:write(pixels:encode('png'):getString());file:close();pixels:release()
                row.shadow_vertices=renderer.shadows.stats.vertices or 0
                row.shadow_static_casters=renderer.shadows.stats.staticCasters or 0
            end
            row.over_16_67ms=0;row.over_33_33ms=0
            for _,sample in ipairs(samples) do
                if sample.frame_ms>1000/60 then row.over_16_67ms=row.over_16_67ms+1 end
                if sample.frame_ms>1000/30 then row.over_33_33ms=row.over_33_33ms+1 end
            end
            report.rows[#report.rows+1]=row;report.samples[name]=samples
            print(('COMPLETE %s mean=%.2fms p95=%.2fms max=%.2fms fps=%.1f'):format(name,row.metrics.frame_ms.mean,row.metrics.frame_ms.p95,row.metrics.frame_ms.max,row.throughput_fps));io.flush()
            writeReport();capture(name..(untilReady and '-ready' or '-final'))
            if fencedPixels then
                local encoded=fencedPixels:encode('png')
                local file=assert(io.open(output..'/'..name..'-gpu-final.png','wb'))
                file:write(encoded:getString());file:close();encoded:release();fencedPixels:release()
            end
        end
        writeReport()
        print(('STARTUP world=%.2fms renderer=%.2fms cockpit=%.2fms'):format(report.startup.world_ms,report.startup.renderer_ms,report.startup.cockpit_ms));io.flush()
        -- Runtime plant pages decode and upload asynchronously, one requested
        -- page at a time. Leave enough frames for that queue to settle on both
        -- the mobile-policy and desktop-policy paths.
        local mobileSettleFrames=1800
        local zoomedSettleFrames=900
        stage('cold_initial_frames',mobileSettleFrames,nil,true)
        if captureOnly then
            camera:setFirstPerson(true,actor);stage('first_person_initial',mobileSettleFrames,nil,true)
            report.complete=true;writeReport();renderer:release();ImageLoader.shutdown();ImageLoader.setEnabled(false);love.event.quit(0);return
        end
        stage('stationary',180)
        stage('ride_streaming',300,function(i) position(i*.3) end)
        stage('camera_rotation',180,function(i) camera.yaw=(20+i*2)%360 end)
        camera.zoom=.55;camera.targetZoom=.55
        stage('zoomed_out_initial',zoomedSettleFrames,nil,true)
        stage('zoomed_out_steady',180)
        camera:setFirstPerson(true,actor)
        stage('first_person_initial',mobileSettleFrames,nil,true)
        stage('first_person_steady',180)
        stage('first_person_streaming',300,function(i) position(90+i*.3) end)
        stage('first_person_rotation',180,function(i) camera:orbit(2,0) end)
        if shadowHour then
            stage('shadow_camera_switches',180,function(i)
                if i%6==1 then camera:setFirstPerson(not camera.firstPerson,actor)end
                camera.yaw=(20+i*2)%360
            end)
        end
        if bridgeStress and renderer.structures then
            local best,bestCount=nil,-1
            for _,road in ipairs(roads.segments) do if road.bridge then
                local x,z=(road.a.x+road.b.x)*.5,(road.a.z+road.b.z)*.5;local n=0
                for _,piece in ipairs(renderer.structures.pieces) do
                    if piece.kind~='building' and (piece.x-x)^2+(piece.z-z)^2<(80+(piece.radius or 0))^2 then n=n+1 end
                end
                if n>bestCount then bestCount=n;best={x=x,z=z,heading=math.atan2(road.b.z-road.a.z,road.b.x-road.a.x),road=road.id} end
            end end
            assert(best,'Bridge stress requested but this town has no bridge')
            report.bridge_stress={x=best.x,z=best.z,road=best.road,nearby_bridge_pieces=bestCount,radius=80}
            actor.x,actor.z,actor.heading,actor.speed=best.x,best.z,best.heading,0
            actor.h=world:supportHeight(actor.x,actor.z)
            camera=Camera.new(actor,world);camera.zoom=.55;camera.targetZoom=.55;camera.yaw=20
            stage('bridge_initial',1800,nil,true)
            stage('bridge_steady',180)
            stage('bridge_rotation',180,function(i)camera.yaw=(20+i*2)%360 end)
            camera:setFirstPerson(true,actor)
            stage('bridge_first_person_initial',1200,nil,true)
            stage('bridge_first_person_steady',180)
            stage('bridge_first_person_rotation',180,function(i)camera:orbit(2,0) end)
        end
        report.complete=true;writeReport()
        renderer:release();ImageLoader.shutdown();ImageLoader.setEnabled(false);love.event.quit(0)
    end
end
return P
