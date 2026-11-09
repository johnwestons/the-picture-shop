local PixelCanvas=require('src.tests.support.pixel_canvas')
local Fields=require('src.commute.grass_fields')
local Placement=require('src.commute.grass_placement')
local Test={}
local function digest(fields)
    local records={}
    for key,entry in pairs(fields.cache) do
        local p=entry.patch
        if p then
            local vertices={}
            for i=1,p.mesh:getVertexCount() do
                local v={p.mesh:getVertex(i)}
                for j=1,#v do v[j]=('%.6f'):format(v[j]) end
                vertices[#vertices+1]=table.concat(v,',')
            end
            records[#records+1]=key..':'..table.concat(vertices,';')
        end
    end
    table.sort(records);return table.concat(records,'\n')
end
function Test.run(check)
    local world=require('src.commute.tests.grass_placement_test').fixture()
    local Surface=require('src.commute.vendor.terrain');local original=Surface.surface
    local seconds,steps=Fields.BUILD_SECONDS,Fields.STEPS_PER_FRAME;local a,b
    local okay,reason=xpcall(function()
        Surface.surface=function()return .3,.4,.2,'meadow',.85 end
        Fields.BUILD_SECONDS=math.huge
        local Vegetation=require('src.commute.vegetation');world.vegetation=Vegetation.new(world)
        a=Fields.new(world);b=Fields.new(world)
        local camera={centerX=48,centerZ=48}
        local visible=a:collect(32,32,64,64,camera,22)
        check('grass_fields_limits_patch_builds_each_frame',a:stats().built<=Fields.BUILDS_PER_FRAME and a:stats().generated<=2)
        for _=1,24 do visible=a:collect(32,32,64,64,camera,22) end
        for _=1,24 do b:collect(32,32,64,64,camera,22) end
        check('grass_fields_builds_indexed_native_geometry',#visible>0 and visible[1].indices>visible[1].vertices)
        local triangles=true
        for _,patch in ipairs(visible) do
            triangles=triangles and patch.vertices==#patch.sections*7
                and patch.indices==#patch.sections*9
        end
        check('grass_fields_three_joined_triangles_per_tuft',triangles)
        check('grass_fields_short_draw_distance',Fields.FAR_VIEW_RADIUS<=20 and Fields.GRID<=7)
        check('grass_fields_seeded_blades_match_across_independent_instances',digest(a)==digest(b))
        local rootOkay,sections,footprint=true,0,true
        for _,p in ipairs(visible) do
            for _,section in ipairs(p.sections) do
                sections=sections+1;rootOkay=rootOkay and Placement.sample(world,section.x,section.z)~=nil
                for i=section.firstVertex,section.lastVertex do
                    local x,z,h,bladeHeight=p.mesh:getVertex(i)
                    local extent=((x-section.x)^2+(z-section.z)^2)^.5
                    footprint=footprint and extent+.20*bladeHeight*bladeHeight<=Placement.CLEARANCE
                    if bladeHeight==0 then rootOkay=rootOkay and math.abs(h-world:height(x,z)-.018)<.00001 end
                end
            end
        end
        check('grass_fields_roots_follow_ground_and_stay_in_allowed_material',rootOkay and sections>0)
        check('grass_fields_entire_blade_and_wind_fit_exclusion_clearance',footprint)
        local before=digest(a);local generated=a.generated
        a:collect(32,32,64,64,camera,22)
        check('grass_fields_stationary_camera_reuses_immutable_meshes',a.generated==generated and digest(a)==before)
        local Camera=require('src.commute.camera')
        local actor={x=48,z=48,h=3,heading=0,speed=0}
        local view=Camera.new(actor,world);view:setViewport(640,420)
        a:prepareDraw(view,1,'summer',22,51200,actor)
        a:prepareDraw(view,2,'autumn',22,51200,actor)
        check('grass_fields_wind_and_season_do_not_rebuild_geometry',a.generated==generated and digest(a)==before)
        local g=love.graphics;local canvas=PixelCanvas(640,420)
        local function windPixels(time)
            g.push('all');g.setCanvas({canvas,depth=true});g.origin();g.clear(0,0,0,1,0,1)
            a:prepareDraw(view,time,'summer',22,51200,actor)
            g.setShader(a.shader);g.setDepthMode('lequal',true);g.setColor(1,1,1)
            for _,p in ipairs(visible) do a:drawPatch(p) end
            g.pop();return canvas:newImageData()
        end
        local first,second=windPixels(0),windPixels(2)
        local changed,colored=0,0
        for y=0,419,3 do for x=0,639,3 do
            local ar,ag,ab=first:getPixel(x,y);local br,bg,bb=second:getPixel(x,y)
            if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.025 then changed=changed+1 end
            if ag>.16 and ag>ar and ag>ab then colored=colored+1 end
        end end
        check('grass_fields_native_wind_changes_visible_pixels_with_static_meshes',changed>20 and a.generated==generated)
        check('grass_fields_native_shader_preserves_readable_green_vertex_colors',colored>100)
        first:release();second:release();canvas:release()
        Fields.BUILD_SECONDS=0;a.buildBudgetSeconds=0;camera.centerX=90;camera.centerZ=90
        local previous=a.generated;a:collect(80,80,104,104,camera,16)
        check('grass_fields_zero_time_budget_defers_new_geometry',a.generated==previous and a.buildsThisFrame==0)
        Fields.BUILD_SECONDS=math.huge;a.buildBudgetSeconds=Fields.BUILD_SECONDS
        Fields.STEPS_PER_FRAME=1
        a:collect(80,80,104,104,camera,16);local oldJob=a.job
        check('grass_fields_dense_patch_build_can_suspend_between_cells',oldJob and coroutine.status(oldJob.thread)=='suspended')
        camera.centerX,camera.centerZ=20,100
        a:collect(8,88,32,112,camera,16)
        check('grass_fields_teleport_cancels_unneeded_partial_patch',a.job and a.job.key~=oldJob.key)
        Fields.STEPS_PER_FRAME=steps
        local limit=Fields.MAX_CACHE_ENTRIES;Fields.MAX_CACHE_ENTRIES=8
        local trimmed,trimReason=xpcall(function()
            for step=1,12 do
                camera.centerX=12+step*8;camera.centerZ=32+step%3*8
                for _=1,4 do
                    a:collect(camera.centerX-12,camera.centerZ-12,camera.centerX+12,camera.centerZ+12,camera,16)
                    assert(a.cacheCount<=8 and a.meshBytes<=Fields.MAX_MESH_BYTES)
                end
            end
        end,debug.traceback)
        Fields.MAX_CACHE_ENTRIES=limit
        check('grass_fields_travel_respects_cache_and_gpu_memory_caps',trimmed,trimReason)
        a:release();a:release()
        check('grass_fields_release_is_idempotent_and_frees_cache',a.meshBytes==0 and a.cacheCount==0 and a.shader==nil)
    end,debug.traceback)
    Surface.surface=original;Fields.BUILD_SECONDS=seconds;Fields.STEPS_PER_FRAME=steps
    if a then a:release() end;if b then b:release() end
    assert(okay,reason)
end
return Test
