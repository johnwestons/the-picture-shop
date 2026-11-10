-- Drive the real app to the generated sites and capture both production cameras.
local Commute = require('src.commute.runtime')
local Trip = require('src.commute.trip')
local Bike = require('src.commute.motorcycle')
local Rider = require('src.commute.rider')
local Bindings = require('src.commute.bindings')
local Calendar = require('src.business_calendar')
local Test = {}

local function frame(R,name,meshes)
    local g=love.graphics
    local canvas=g.newCanvas(R.Config.baseWidth,R.Config.baseHeight)
    local draw=g.draw
    local counts={sidewalk=0,streetFurniture=0}
    g.push('all');g.setCanvas({canvas,stencil=true})
    g.draw=function(drawable,...)
        local kind=meshes[drawable]
        if kind then counts[kind]=counts[kind]+1 end
        return draw(drawable,...)
    end
    local ok,reason=xpcall(R.App.draw,debug.traceback)
    g.draw=draw;g.pop()
    if not ok then canvas:release();error(reason,0) end
    local directory=os.getenv('PICTURE_SHOP_COMMUTE_CAPTURE')
    if directory then
        local pixels=canvas:newImageData();local encoded=pixels:encode('png')
        local file=assert(io.open(directory..'/'..name..'.png','wb'))
        file:write(encoded:getString());file:close();encoded:release();pixels:release()
    end
    canvas:release()
    return counts
end

local function findViewpoint(world,target,role)
    local best,bestScore
    for _,segment in ipairs(world.roads.segments) do
        if segment.role==role and not segment.bridge then
            local x,z=(segment.a.x+segment.b.x)*.5,(segment.a.z+segment.b.z)*.5
            local dx,dz=target.x-x,target.z-z
            local distance=math.sqrt(dx*dx+dz*dz)
            local score=math.abs(distance-7)
            if target.kind=='stop' then
                -- View the lettering from the signed approach, not the back of the plate.
                local facing=-(dx*target.fx+dz*target.fz)/math.max(distance,.01)
                score=score+(1-facing)*14
            end
            if target.roadId and segment.id~=target.roadId then score=score+12 end
            if distance>=4 and (not bestScore or score<bestScore) and Rider.clear(world,x,z,Bike.RADIUS) then
                best={x=x,z=z,heading=math.atan2(dz,dx)};bestScore=score
            end
        end
    end
    return assert(best,'No clear viewpoint for '..tostring(target.kind))
end

local function settle(R)
    local renderer=R._commute.renderer
    local deadline=love.timer.getTime()+60
    local i=0
    repeat
        i=i+1
        R.App.update(1/60)
        if i>=30 and renderer:terrainReady() and renderer.vegetation:stats().pending==0 and
            renderer.plantSprites:readyFor(renderer.visibleProps,renderer.calendar,renderer.clock) then break end
        assert(love.timer.getTime()<deadline,'Infrastructure view did not finish streaming')
    until false
end

local function inspect(R,meshes,target,role,name,check)
    local part=Commute.localPart(R)
    local bike=part.rider.bike
    local world=Commute.world(R)
    local pose=findViewpoint(world,target,role)
    bike.x,bike.z,bike.heading,bike.speed=pose.x,pose.z,pose.heading,0
    Bike.resetHorizontal(bike);Bike.resetContact(bike,world)
    Commute.syncPlayer(R.World.player,part)
    local camera=R._commute.camera
    camera:setFirstPerson(false,bike);camera:recenter()
    camera.yaw=(-bike.heading*180/math.pi-90)%360
    camera.fixedYaw=camera.yaw;camera.tilt=55
    camera.zoom,camera.targetZoom=1.1,1.1
    settle(R)
    local outside=frame(R,name..'-outside',meshes)
    R.App.keypressed('p');assert(camera.firstPerson);camera:recenter();settle(R)
    local first=frame(R,name..'-first-person',meshes)
    R.App.keypressed('p');assert(not camera.firstPerson)
    check('infrastructure_runtime_shared_fixture_meshes_drawn_in_both_views_'..name,
        outside.streetFurniture>0 and first.streetFurniture>0,
        ('outside=%d firstPerson=%d'):format(outside.streetFurniture,first.streetFurniture))
end

local function overview(R,meshes,area,check)
    local part=Commute.localPart(R);local bike=part.rider.bike
    local world=Commute.world(R);local layout=require('src.commute.recreation_layout')
    bike.x,bike.z=layout.point(area,0,area.radius*.2)
    bike.heading,bike.speed=(area.heading or 0)+math.pi,0
    Bike.resetHorizontal(bike);Bike.resetContact(bike,world)
    Commute.syncPlayer(R.World.player,part)
    local camera=R._commute.camera
    camera:setFirstPerson(false,bike);camera:setOutsideMode('fixed',bike,true);camera:recenter()
    camera.yaw=(-bike.heading*180/math.pi-90)%360;camera.fixedYaw=camera.yaw
    camera.tilt=60;camera.zoom,camera.targetZoom=.55,.55
    settle(R)
    local shown=R.App.settings.hudVisible;R.App.settings.hudVisible=false
    local rendered=frame(R,'infra-'..area.kind..'-overview',meshes)
    R.App.settings.hudVisible=shown
    check('infrastructure_runtime_expanded_'..area.kind..'_renders_in_generated_terrain',rendered.streetFurniture>0)
end

function Test.run(context,check)
    local R=assert(context.appRuntime)
    local oldProfile,oldMovement,oldDrive=R.App.settings.motorcycleControls,R.Input.movement,Bindings.drive
    R.App.settings.motorcycleControls=Bindings.defaults()
    R.Input.movement=function()return 0,0 end;Bindings.drive=function()return 0,0,false end
    local success,reason=xpcall(function()
        R.Save.delete(3)
        local town=assert(require('src.commute.town').generate(712345))
        assert(R.startGame(assert(R.Save.newGame(3,{apartmentId='garden',town=town})),'smoke'))
        R.state.screen='world';R.state.calendar=Calendar.dateFromHours(58)
        R.state.calendar.elapsed=58%24/24*Calendar.secondsPerDay(R.state)
        local week=R.state.home.weekend
        week.phase='ready';week.closedAtHours=44;week.travelToken=98;week.readyMask=1
        local world=Commute.world(R)
        assert(Trip.start(R.state,{R.World.player},98,world))
        Commute.syncPlayer(R.World.player,Commute.localPart(R))
        R._weekendPromptToken=98;R._weekendScene='commute'
        require('src.commute.tests.loading_test_support').wait(R,check,'infrastructure_runtime')
        local renderer=R._commute.renderer;local plan=assert(world.infrastructure)
        local part=Commute.localPart(R)
        part.rider.gear={version=1,outfit='geared',mounted=true,engine=true,revision=1}
        local meshes={};local tiles,vertices=0,0
        for _,piece in ipairs(renderer.structures.pieces) do
            if piece.kind=='streetFurniture' or piece.kind=='sidewalk' then
                meshes[piece.mesh]=piece.kind;tiles=tiles+1;vertices=vertices+piece.vertexCount
            end
        end
        local counts=plan.counts
        print(('INFRASTRUCTURE_NATIVE main=%s lamps=%d mailboxes=%d stops=%d curves=%d rails=%d recreation=%d tiles=%d vertices=%d')
            :format(town.topology.mainStreet.pattern,counts.lamp or 0,counts.mailbox or 0,counts.stop or 0,
                counts.curve or 0,#plan.rails,#town.recreation,tiles,vertices))
        check('infrastructure_runtime_registered_collision_and_render_fixtures',world.roads.infrastructure==plan and
            counts.lamp>0 and counts.mailbox>0 and counts.stop>0 and #plan.walks>0 and #town.recreation>=2
            and tiles>0 and vertices>0)
        local mainRoads={}
        for _,id in ipairs(town.topology.mainStreet.roadIds) do mainRoads[id]=true end
        local lamp,curve,camp,picnic,stop,bestLamp
        local station=world.sites.byId['fire-station']
        for _,f in ipairs(plan.fixtures) do
            if f.kind=='lamp' and mainRoads[f.roadId] then
                local score=(f.x-station.door.x)^2+(f.z-station.door.z)^2
                if not bestLamp or score<bestLamp then lamp,bestLamp=f,score end
            end
            if f.kind=='curve' then curve=curve or f end
            if f.kind=='tent' then camp=camp or f end
            if f.kind=='table' then picnic=picnic or f end
            if f.kind=='stop' then stop=stop or f end
        end
        inspect(R,meshes,assert(lamp),'main','infra-main-street',check)
        R.App.keypressed('m');assert(R._commute.mapOpen)
        frame(R,'infra-town-map',meshes);local map=R._commute.routeMap
        R.App.keypressed('m');assert(not R._commute.mapOpen)
        inspect(R,meshes,assert(camp),'trail','infra-recreation',check)
        inspect(R,meshes,assert(picnic),'trail','infra-picnic-table',check)
        for _,area in ipairs(town.recreation) do
            if require('src.commute.recreation_layout').expanded(area) then overview(R,meshes,area,check) end
        end
        local stopRole=mainRoads[assert(stop).roadId] and 'main' or 'local'
        inspect(R,meshes,stop,stopRole,'infra-stop-sign',check)
        if #plan.rails>0 then
            local rail=plan.rails[1];local path=world.roads.paths
            local role='local';for _,p in ipairs(path) do if p.id==rail.roadId then role=p.role end end
            inspect(R,meshes,rail,role,'infra-guardrail',check)
        end
        if curve then
            local role=mainRoads[curve.roadId] and 'main' or 'local'
            inspect(R,meshes,curve,role,'infra-curve-sign',check)
        end
        assert(R.returnToTitle())
        check('infrastructure_runtime_exit_releases_both_views_and_map',R.state.screen=='title' and
            R._commute==nil and renderer.released and map.released and map.background==nil)
    end,debug.traceback)
    R.Input.movement,Bindings.drive,R.App.settings.motorcycleControls=oldMovement,oldDrive,oldProfile
    if not success then Commute.release(R);error(reason,0) end
end
return Test
