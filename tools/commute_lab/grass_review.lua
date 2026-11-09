local Review={}
local function save(canvas,path)
    local data=canvas:newImageData();local png=data:encode('png')
    local file=assert(io.open(path,'wb'));file:write(png:getString());file:close()
    png:release();data:release()
end
function Review.install()
    function love.load()
        local count=0
        local function check(name,okay,detail)
            assert(okay,name..': '..tostring(detail or 'check failed'));count=count+1;print('PASS '..name)
        end
        for _,name in ipairs({'grass_placement','grass_fields','terrain_renderer'}) do
            require('src.commute.tests.'..name..'_test').run(check)
        end
        if os.getenv('PICTURE_SHOP_GRASS_UNIT_ONLY')=='1' then
            print('GRASS_UNIT_OK '..count..' checks');love.event.quit(0);return
        end
        Review.scenes(check)
        print('GRASS_REVIEW_OK '..count..' checks; native fixed, follow and first-person scenes')
        love.event.quit(0)
    end
end
function Review.scenes(check)
    local g=love.graphics;local output=assert(os.getenv('PICTURE_SHOP_GRASS_OUTPUT'))
    local Town=require('src.commute.town');local Placement=require('src.commute.grass_placement')
    local Camera=require('src.commute.camera');local Renderer=require('src.commute.renderer')
    local M=require('src.commute.vendor.mathx');local Flora=require('src.commute.flora')
    local world=Town.world(assert(Town.generate(4261)))
    world.calendar={month=6,totalDays=0}
    local meadow,coast,best=nil,nil,-1
    for x=24,488,8 do for z=24,488,8 do
        local h,grass=Placement.sample(world,x,z)
        if h then
            local canopy=world:habitat(x,z)
            local field=M.smooth((M.noise(world.seed+1807,x*.038,z*.038)-.45)/.26)
            local cluster=M.smooth((M.noise(world.seed+2371,x*.13,z*.13)-.42)/.26)
            local score=grass*(1-canopy)*field*cluster
            if score>best then best=score;meadow={x=x,z=z,h=h,label='meadow'} end
        end
        local shore=world.plan:shoreDistance(x,z)
        if shore>2 and shore<7 and world:rawHeight(x,z)>.5 then coast={x=x,z=z,h=world:height(x,z),label='coast'} end
    end end
    assert(meadow,'No suitable meadow in native fixture')
    local trail,road
    for _,p in ipairs(world.roads.paths) do
        local s=p.points[math.max(1,math.floor(#p.points/2))]
        local destination={x=s.x,z=s.z,h=s.h,label=p.surface=='dirt' and 'trail' or 'road'}
        if p.surface=='dirt' and not trail then trail=destination
        elseif p.surface~='dirt' and not road then road=destination end
    end
    assert(road and trail and coast,'Native review requires road, trail and coast')
    local renderer=Renderer.new(world);renderer:resizeViewport(960,640)
    local actor={x=meadow.x-2,z=meadow.z,h=meadow.h,heading=0,speed=0,lean=0,distance=0,grounded=true}
    local camera=Camera.new(actor,world);camera:setViewport(960,640);camera.zoom=.8;camera.targetZoom=.8
    for _=1,1000 do renderer:prepare(camera,1/60);if renderer:terrainReady() then break end end
    assert(renderer:terrainReady(),'Native terrain build did not finish')
    renderer:prewarmViews()
    local canvas=g.newCanvas(960,640);local records={};local allRoots,totalSections,maxBuild=true,0,0
    local function capture(location,mode)
        actor.x,actor.z,actor.h=location.x-2,location.z,world:supportHeight(location.x-2,location.z)
        actor.heading=mode=='first' and math.atan2(location.z-actor.z,location.x-actor.x) or 0
        camera:setOutsideMode(mode=='follow' and 'follow' or 'fixed',actor,true)
        camera:setFirstPerson(mode=='first',actor)
        camera.centerX,camera.centerZ=actor.x,actor.z
        if mode=='first' then
            camera.viewPitch=-.14;camera.roll=.03
        else camera.yaw=mode=='follow' and camera.yaw or 25;camera.fixedYaw=camera.yaw end
        for _=1,80 do renderer:prepare(camera,1/60);maxBuild=math.max(maxBuild,renderer.grassFields.buildMs) end
        local sections=0
        for _,patch in ipairs(renderer.visibleGrass or {}) do
            for _,section in ipairs(patch.sections) do
                sections=sections+1;allRoots=allRoots and Placement.sample(world,section.x,section.z)~=nil
            end
        end
        totalSections=totalSections+sections
        local calls=0;local original=renderer.grassFields.drawPatch
        renderer.grassFields.drawPatch=function(self,patch)
            calls=calls+1;local depth,write=g.getDepthMode()
            assert(depth=='lequal' and write,'Grass must share scene depth')
            return original(self,patch)
        end
        g.push('all');g.setCanvas({canvas,depth=true});g.origin();g.clear(.2,.27,.26,1,0,1)
        renderer:draw(camera,actor,{{actor=actor,localPlayer=true}})
        g.setShader();g.setColor(1,1,1);g.print(location.label..' / '..mode,16,16)
        g.print(('Grass patches %d | triangle tufts %d'):format(calls,sections),16,36)
        g.pop();renderer.grassFields.drawPatch=original
        check('grass_native_'..location.label..'_'..mode..'_submits_cached_depth_tested_meshes',calls==#renderer.visibleGrass)
        if location==meadow then check('grass_native_meadow_'..mode..'_has_visible_grass',sections>0) end
        save(canvas,output..'/'..location.label..'-'..mode..'.png')
        local stats=renderer.grassFields:stats()
        check('grass_native_'..location.label..'_'..mode..'_keeps_cache_bounded',stats.patches<=196 and stats.meshBytes<=12*1024*1024)
        records[#records+1]=('%s %s: %d sections, %d patches, %d bytes'):format(location.label,mode,sections,calls,stats.meshBytes)
    end
    for _,location in ipairs({meadow,road,trail,coast}) do
        capture(location,'fixed');capture(location,'first')
    end
    capture(meadow,'follow')
    check('grass_native_every_generated_section_respects_town_material_and_setbacks',allRoots and totalSections>0)
    check('grass_native_grass_does_not_enter_obstacle_collision_registry',world.vegetation:stats().patches<=256
        and not require('src.commute.obstacles').solidKind('grass'))
    records[#records+1]=('Peak single grass prepare: %.3f ms; total reviewed sections: %d'):format(maxBuild,totalSections)
    local file=assert(io.open(output..'/native-report.txt','wb'));file:write(table.concat(records,'\n')..'\n');file:close()
    canvas:release();renderer:release()
end
return Review
