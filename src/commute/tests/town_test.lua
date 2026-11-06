local Town=require('src.commute.town')
local Sites=require('src.commute.sites')
local Codec=require('src.net.codec')
local Schema=require('src.save_schema')
local Test={}
local limits={maxBytes=512*1024,maxDepth=32,maxEntries=32768,maxStringBytes=128*1024,maxNumberBytes=32}
Test.codecLimits=limits
function Test.fixture(town,crowded)
    local state=Schema.defaultState()
    state.home=assert(require('src.home').new({town=town},state.calendar.totalDays))
    if crowded then
        local Fleet=require('src.machine_fleet')
        local starter=Schema.copy(Fleet.ensure(state).items[1])
        for index=3,14 do
            local item=Schema.copy(starter);item.id=('MCH-%04d'):format(index);item.serial='PS-'..item.id
            item.world={x=350+((index-3)%6)*75,y=320+math.floor((index-3)/6)*210,direction='northwest'}
            state.machines.items[#state.machines.items+1]=item
        end
        Fleet.ensure(state)
        local Jobs=require('src.jobs')
        for index=1,80 do
            local job=assert(Jobs.createOffer({id='TOWN-CROWD-'..index,company='Town capacity fixture',
                sourceSize={width=20,height=16},finishedSize={width=10,height=8},sheetCounts={500}}))
            Jobs.accept(job);state.jobs.active[#state.jobs.active+1]=job
            for _,pallet in ipairs(job.pallets) do
                pallet.location='warehouse';pallet.world={x=310+((index-1)%10)*50,
                    y=380+math.floor((index-1)/10)*14,direction='northwest'}
            end
        end
        local Employees=require('src.employees');local Calendar=require('src.business_calendar')
        state.money=1000000
        local function hours(h)
            state.calendar=Calendar.dateFromTotalDay(math.floor(h/24))
            state.calendar.elapsed=(h%24)/24*Calendar.secondsPerDay(state)
        end
        local applicant=assert(Employees.createApplicant(state,0))
        assert(Employees.requestResume(state,applicant.id,0))
        hours(.5);Employees.advance(state,.5)
        assert(Employees.command(state,{kind='offer_employee',applicationId=applicant.id,
            expectedRevision=applicant.revision,wageCents=10000,days=31,startHour=9,endHour=17},.5))
        hours(1.25);Employees.advance(state,1.25)
        assert(Employees.command(state,{kind='hire_employee',applicationId=applicant.id,
            expectedRevision=applicant.revision},1.25))
        for index=2,10 do
            local employee=Schema.copy(state.employment.staff[1]);employee.id=('EMP-%04d'):format(index)
            state.employment.staff[index]=employee
        end
        state.employment.nextEmployeeId=11;hours(9.25);state.employment.lastAtHours=9.25
        for index,employee in ipairs(state.employment.staff) do
            employee.visible=true;employee.phase='idle';employee.x=330+index*40;employee.y=580
        end
        assert(Employees.valid(state.employment))
        Schema.reconcile(state)
    end
    return state
end
function Test.run(check)
    require('src.commute.tests.town_generation_test').run(check)
    local town=assert(Town.generate(712345))
    local repeated=assert(Town.generate(712345));local different=assert(Town.generate(712346))
    local encoded=assert(Codec.encode(town,limits))
    check('town_same_seed_reproduces_complete_frozen_layout',encoded==assert(Codec.encode(repeated,limits)))
    check('town_different_seed_changes_roads_terrain_and_placement',
        assert(Codec.encode(town.roads,limits))~=assert(Codec.encode(different.roads,limits))
        and assert(Codec.encode(town.placements,limits))~=assert(Codec.encode(different.placements,limits))
        and town.terrain.heights[120]~=different.terrain.heights[120])
    local world=Town.world(town)
    -- Town.world attaches a generated fuel station to legacy and current
    -- saved towns without mutating their frozen placement records.
    local coverage=#world.sites.all==17
    for _,id in ipairs({'warehouse','brick-walkup','garden','courtyard','corner','mechanic','grocery',
        'post-office','police','fire-station','diner','coffee-shop','general-store',
        'residential-1','residential-2','residential-3'}) do
        local site=world.sites.byId[id]
        local pad=id=='gas-station' and world.town.destinations[id] or town.destinations[id]
        coverage=coverage and site and pad and math.abs(pad.x-site.parking.x)<1e-6
            and math.abs(pad.z-site.parking.z)<1e-6 and not site:blocked(site.door.x,site.door.z)
    end
    check('town_has_all_sixteen_registered_buildings_and_clear_entrances',coverage)
    check('town_world_construction_does_not_rewrite_saved_specification',assert(Codec.encode(town,limits))==encoded)
    local originalWidth=Sites.designs.warehouse.width
    Sites.designs.warehouse.width=originalWidth+100
    local okay,stable=pcall(function()
        local rebuilt=Town.world(town)
        return rebuilt.sites.byId.warehouse.design.width==originalWidth
            and rebuilt.plan.grid[1][54]==town.terrain.heights[120]
            and assert(Codec.encode(town,limits))==encoded
    end)
    Sites.designs.warehouse.width=originalWidth
    check('town_frozen_design_and_terrain_survive_catalog_changes',okay and stable)
    local removed=Sites.designs.warehouse;Sites.designs.warehouse=nil
    local survivesRemoval,removedWorld=pcall(Town.world,town)
    Sites.designs.warehouse=removed
    check('town_frozen_design_survives_live_catalog_entry_removal',survivesRemoval
        and removedWorld.sites.byId.warehouse.design.style=='warehouse')
    local decoded=assert(Codec.decode(encoded,limits))
    check('town_codec_arrays_remain_valid',Town.valid(decoded))
    check('town_decoded_snapshot_builds_the_same_world',Town.world(decoded).townId==world.townId
        and assert(Codec.encode(decoded,limits))==encoded)
    local function rejected(edit)
        local bad=Town.copy(town);edit(bad);local success,result=pcall(Town.valid,bad)
        return success and not result
    end
    check('town_rejects_invalid_foundation',rejected(function(t)t.designs.warehouse.foundation={minX=1,maxX=-1,minZ=-2,maxZ=2}end))
    check('town_rejects_nonfinite_obstacles',rejected(function(t)t.designs.warehouse.obstacles={{minX=0,maxX=1,minZ=0,maxZ=math.huge}}end))
    check('town_rejects_obstacles_blocking_entry',rejected(function(t)t.designs.warehouse.obstacles={{minX=3,maxX=4,minZ=3,maxZ=4}}end))
    check('town_rejects_cyclic_designs',rejected(function(t)t.designs.warehouse.extra=t end))
    check('town_rejects_unsupported_styles',rejected(function(t)t.designs.warehouse.style='not-supported' end))
    check('town_rejects_invalid_saved_seed',rejected(function(t)t.seed=0 end)
        and rejected(function(t)t.seed=1.5 end) and rejected(function(t)t.seed=math.huge end))
    check('town_rejects_invalid_generation_seed',Town.generate(0)==nil and Town.generate(-1)==nil
        and Town.generate(1.5)==nil and Town.generate(Town.MAX_SEED+1)==nil)
    for _,crowded in ipairs({false,true}) do
        local snapshot=assert(Schema.snapshot(Test.fixture(town,crowded)))
        local packet,encodeError=Codec.encode(snapshot,limits)
        local restored=packet and Codec.decode(packet,limits)
        check(crowded and 'town_crowded_snapshot_fits_reliable_limits' or 'town_snapshot_fits_reliable_limits',
            packet~=nil and #packet<limits.maxBytes and restored~=nil and Schema.validState(restored),encodeError)
        local Protocol=require('src.net.protocol')
        local reliable=assert(Protocol.encode('shop_state',{sessionId='town-test',revision=1,state=snapshot}))
        local envelope=assert(Protocol.decode(reliable))
        check(crowded and 'town_crowded_reliable_envelope_roundtrips' or 'town_reliable_envelope_roundtrips',
            #reliable<Protocol.packetLimitFor('shop_state') and Schema.validState(envelope.payload.state))
        check(crowded and 'town_crowded_snapshot_preserves_frozen_layout' or 'town_snapshot_preserves_frozen_layout',
            restored and assert(Codec.encode(restored.home.town,limits))==encoded)
    end
end
return Test
