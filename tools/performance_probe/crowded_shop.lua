-- Synthetic capacity fixture: deliberately dense, repeatable, private state.
return function(runtime, app, measure, draw, rows)
    local Fleet = require("src.machine_fleet")
    local Schema = require("src.save_schema")
    local Employees = require("src.employees")
    local Calendar = require("src.business_calendar")
    local state = runtime.state
    state.activeSlot = nil
    state.screen = "world"
    state.forklift.operating = false
    state.forklift.operatorPlayerId = nil
    state.forklift.owned = false
    state.warehouse.forkliftOwned = false
    state.money = 1000000
    local starter = Schema.copy(Fleet.ensure(state).items[1])
    for index = 3, 14 do
        local item = Schema.copy(starter)
        item.id = string.format("MCH-%04d", index)
        item.serial = "PS-" .. item.id
        item.world = {x=350+((index-3)%6)*75, y=320+math.floor((index-3)/6)*210, direction="northwest"}
        state.machines.items[#state.machines.items+1] = item
    end
    Fleet.ensure(state)
    for index = 1, 80 do
        local job = assert(runtime.Jobs.createOffer({id="CROWD-"..index,company="Capacity fixture",
            sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
        runtime.Jobs.accept(job)
        state.jobs.active[#state.jobs.active+1] = job
        for _, pallet in ipairs(job.pallets) do
            pallet.location = "warehouse"
            pallet.world = {x=310+((index-1)%10)*50,y=380+math.floor((index-1)/10)*14,direction="northwest"}
        end
    end
    local function hours(h)
        state.calendar=Calendar.dateFromTotalDay(math.floor(h/24))
        state.calendar.elapsed=(h%24)/24*Calendar.secondsPerDay(state)
    end
    local applicant = assert(Employees.createApplicant(state,0))
    assert(Employees.requestResume(state,applicant.id,0))
    hours(.5);Employees.advance(state,.5)
    assert(Employees.command(state,{kind="offer_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision,wageCents=10000,days=31,startHour=9,endHour=17},.5))
    hours(1.25);Employees.advance(state,1.25)
    assert(Employees.command(state,{kind="hire_employee",applicationId=applicant.id,
        expectedRevision=applicant.revision},1.25))
    local worker=state.employment.staff[1]
    for index=2,10 do
        local copy=Schema.copy(worker)
        copy.id=string.format("EMP-%04d",index)
        state.employment.staff[index]=copy
    end
    state.employment.nextEmployeeId=11
    hours(9.25)
    state.employment.lastAtHours=9.25
    for index,w in ipairs(state.employment.staff) do
        w.visible=true;w.phase="idle";w.x=330+index*40;w.y=580
    end
    assert(Employees.valid(state.employment),"Invalid crowd workforce")
    measure("crowded_world_update_14_machines_80_pallets_10_staff",180,function() app.update(1/60) end)
    measure("crowded_world_draw",90,draw)
    local snapshot=assert(Schema.snapshot(state))
    assert(Schema.validState(snapshot),"Crowded fixture must be a valid save")
    measure("crowded_save",3,function() assert(runtime.Save.save(1,state,runtime.World.snapshot())) end)
    state.activeSlot=1
    measure("crowded_gameplay_with_saves",600,function() app.update(1/60) end)
    state.activeSlot=nil
    measure("crowded_machine_lookup",1000,function()
        for _,item in ipairs(state.machines.items) do assert(Fleet.byId(state,item.id)==item) end
    end)
    local Navigation=require("src.navigation")
    local obstacles={}
    for i=1,100 do obstacles[i]={x=80+(i%20)*40,y=250+math.floor(i/20)*30,halfWidth=12,halfHeight=8} end
    local assets={getData=function() return nil end}
    measure("crowded_clear_traversal",300,function()
        assert(Navigation.canTraverse(assets,100,600,850,600,obstacles))
    end)
    local Navigator=require("src.npc_navigation")
    local pathContext={assets=assets,obstacles=function() return obstacles end}
    measure("crowded_route_detour",20,function()
        assert(Navigator.findPath({x=100,y=200},{{x=850,y=500}},pathContext))
    end)
    local characters=runtime.CharacterAssets
    measure("character_action_working_set",1,function()
        characters.retainCharacters({"rabbit-worker"},true)
        for _,action in ipairs(characters.actions("rabbit-worker")) do
            if characters.beginFrame then characters.beginFrame() end
            assert(characters.get("rabbit-worker",action,1))
            if characters.endFrame then characters.endFrame() end
        end
    end)
    rows[#rows].active_texture_bytes=characters.textureBytes()
    rows[#rows].cached_texture_bytes=characters.cachedTextureBytes()
    rows[#rows].resident_actions=characters.residentActionCount()
    print(string.format("character working set active=%.1fMiB cached=%.1fMiB actions=%d",
        characters.textureBytes()/1048576,characters.cachedTextureBytes()/1048576,characters.residentActionCount()))
end
