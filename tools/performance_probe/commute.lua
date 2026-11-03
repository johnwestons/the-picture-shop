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
        report.startup.modules_ms=(timer()-start)*1000
        instrument(Renderer,'build','terrain_build')
        instrument(Renderer,'buildStep','terrain_build')
        instrument(Renderer,'props','props')
        instrument(Renderer,'buildRoadMeshes','road_meshes')
        instrument(require('src.commute.vegetation'),'visible','vegetation_visible')
        instrument(require('src.commute.vendor.plant_sprites'),'prepare','plant_prepare')
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
            local Town=require('src.commute.town');local generated=assert(Town.generate(townSeed))
            world=Town.world(generated);roads=world.roads
            report.town={seed=townSeed,id=world.townId,generator_version=generated.generatorVersion,
                buildings=#roads.sites.all,road_segments=#roads.segments}
        else roads=Roads.new();world=roads:attach(Terrain.new()) end
        report.startup.world_ms=(timer()-start)*1000
        start=timer();local renderer=Renderer.new(world)
        report.startup.renderer_ms=(timer()-start)*1000
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
        local route=assert(require('src.commute.routes').new(roads):find('warehouse','brick-walkup'))
        local spawn=roads.destinations.warehouse
        local heading=townSeed and math.atan2(route.points[2].z-spawn.z,route.points[2].x-spawn.x) or -.7
        local rider=Rider.new(spawn.x,spawn.z,heading,{version=1,outfit='geared',mounted=true,engine=true,revision=0})
        Rider.update(rider,{},0,world)
        local actor=rider.bike;local camera=Camera.new(actor,world)
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
            love.graphics.origin();renderer:draw(camera,actor,{{actor=actor,bikeOnly=false}})
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
                local t=timer();Rider.update(rider,{},1/60,world)
                if not name:find('streaming',1,true) then actor.x,actor.z,actor.speed=heldX,heldZ,0 end
                if update then update(index) end
                camera:updateRide(rider,1/60)
                frame.update_ms=(timer()-t)*1000
                t=timer();renderer:prepare(camera,1/60);frame.prepare_ms=(timer()-t)*1000
                t=timer();love.graphics.origin();love.graphics.clear(.03,.04,.04,1)
                renderer:draw(camera,actor,{{actor=actor,bikeOnly=false}})
                cockpit:draw(actor,rider.gear.engine,1280,880,nil,camera)
                love.graphics.flushBatch();frame.draw_ms=(timer()-t)*1000
                local graphics=love.graphics.getStats()
                frame.draw_calls=graphics.drawcalls;frame.texture_bytes=graphics.texturememory
                local finalFrame=index==count
                if untilReady and index>=60 then
                    finalFrame=finalFrame or ((renderer.pending or 0)==0 and renderer.vegetation:stats().pending==0
                        and frame.plant_ready and renderer.plantSprites:readyFor(renderer.visibleProps,renderer.calendar,renderer.clock))
                end
                if gpuFence and finalFrame then
                    love.graphics.captureScreenshot(function(data) fencedPixels=data end)
                end
                t=timer();love.graphics.present();frame.present_ms=(timer()-t)*1000
                frame.frame_ms=(timer()-began)*1000
                frame.pending=renderer.pending or 0;frame.visible_chunks=#(renderer.visible or {})
                frame.visible_props=#(renderer.visibleProps or {})
                frame.radius=renderer.effectiveRadius or 0
                frame.vegetation_pending=renderer.vegetation:stats().pending or 0
                frame.plant_upload_bytes=renderer.plantSprites.lastPrepareBytes or 0
                frame.plant_motion_bytes=renderer.plantSprites.motionBytes or 0
                frame.actor_x,frame.actor_z,frame.actor_speed=actor.x,actor.z,actor.speed
                frame.camera_x,frame.camera_z=camera.centerX,camera.centerZ
                samples[#samples+1]=frame
                local ready=frame.pending==0 and frame.vegetation_pending==0 and frame.plant_ready
                    and renderer.plantSprites:readyFor(renderer.visibleProps,renderer.calendar,renderer.clock)
                if ready and not readyAt then readyAt=index end
                if index<=3 or index%60==0 then
                    print(('%s %d frame=%.2fms prep=%.2fms vegetation=%.2fms terrain=%.2fms draw=%.2fms present=%.2fms pending=%d'):format(
                        name,index,frame.frame_ms,frame.prepare_ms,frame.vegetation_visible_ms or 0,frame.terrain_build_ms or 0,frame.draw_ms,frame.present_ms,frame.pending));io.flush()
                end
                frame=nil
                if index==1 then capture(name..'-first') end
                if untilReady and ready and index>=60 then break end
            end
            local stageElapsed=timer()-stageStarted
            if profiler then profiler.stop() end
            assert(not gpuFence or fencedPixels,'Stage GPU readback did not complete: '..name)
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
        stage('cold_initial_frames',600,nil,true)
        if captureOnly then
            camera:setFirstPerson(true,actor);stage('first_person_initial',600,nil,true)
            report.complete=true;writeReport();renderer:release();love.event.quit(0);return
        end
        stage('stationary',180)
        stage('ride_streaming',300,function(i) position(i*.3) end)
        stage('camera_rotation',180,function(i) camera.yaw=(20+i*2)%360 end)
        camera.zoom=.55;camera.targetZoom=.55
        stage('zoomed_out_initial',300,nil,true)
        stage('zoomed_out_steady',180)
        camera:setFirstPerson(true,actor)
        stage('first_person_initial',600,nil,true)
        stage('first_person_steady',180)
        stage('first_person_streaming',300,function(i) position(90+i*.3) end)
        stage('first_person_rotation',180,function(i) camera:orbit(2,0) end)
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
        renderer:release();love.event.quit(0)
    end
end
return P
