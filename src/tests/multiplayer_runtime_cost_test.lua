local Test={}
function Test.run(check)
    local State=require('src.state')
    local Home=require('src.home')
    local Town=require('src.commute.town')
    local Residents=require('src.home_residents')
    local Schema=require('src.save_schema')
    local Replication=require('src.net.shop_replication')
    local Windmill=require('src.windmill')
    local state=State.new()
    state.home=assert(Home.new({townSeed=712345}))
    local host={id=1,name='Host',sceneId='warehouse'}
    for i=1,3 do
        assert(Residents.bind(state,{id=i+1,name='Worker '..i,sceneId='warehouse'},
            string.rep(tostring(i),64),{host}))
    end
    local original,calls=Town.valid,0
    Town.valid=function(...)calls=calls+1;return original(...)end
    local okay,valid=pcall(Home.valid,state.home)
    Town.valid=original
    check('lan_four_households_validate_shared_town_once',okay and valid and calls==1,'calls='..calls)
    local prior=state.home.town.size;state.home.town.size=1
    check('lan_town_validation_does_not_cache_across_calls',not Home.valid(state.home))
    state.home.town.size=prior
    local private=state.home.clientHomes['guest-2']
    local balance=private.balanceCents;private.balanceCents=-1
    check('lan_private_household_still_validated',not Home.valid(state.home))
    private.balanceCents=balance
    Windmill.update(0,state)
    local before=assert(Schema.snapshot(Replication.project(state)))
    for _=1,120 do Windmill.update(1/60,state) end
    local after=assert(Schema.snapshot(Replication.project(state)))
    check('lan_idle_windmill_does_not_dirty_shop_state',Replication.diff(before,after)==nil)
    local guest=State.new();assert(State.applySharedSnapshot(guest,before))
    local originalHome,originalJobs,originalPress=guest.home,guest.jobs,guest.windmill
    after.calendar.elapsed=after.calendar.elapsed+.25
    after.home.revision=after.home.revision+1
    local delta=Replication.diff(before,after)
    assert(State.applySharedUpdate(guest,after,Replication.changed(delta)))
    check('lan_routine_update_preserves_unchanged_production',guest.home~=originalHome
        and guest.jobs==originalJobs and guest.windmill==originalPress)

    local Traffic=require('src.commute.delivery_traffic')
    local Routes=require('src.commute.routes')
    local Commuters=require('src.commute.commuter_routes')
    local Copy=Replication.copy
    local world=Town.world(state.home.town)
    Traffic.actors(state,state.home.town,8,1000,world)
    local route=Commuters.route(state.home.town,'warehouse','mainland_exit',world)
    local originalNew,builds=Routes.new,0
    Routes.new=function(...)builds=builds+1;return originalNew(...)end
    local reused,rebuilt
    local success,err=xpcall(function()
        local town=Copy(state.home.town)
        Traffic.actors(state,town,8,1000,world)
        reused=Commuters.route(town,'warehouse','mainland_exit',world)==route and builds==0
        local nextWorld=Town.world(town)
        Traffic.actors(state,town,8,1000,nextWorld)
        rebuilt=Commuters.world(town,nextWorld)==nextWorld and builds>0
    end,debug.traceback)
    Routes.new=originalNew
    assert(success,err)
    check('lan_snapshot_copies_reuse_loaded_world_routes',route~=nil and reused)
    check('lan_replacement_world_rebuilds_routes',rebuilt)

    local Detail=require('src.commute.gps_map_detail')
    local detail=Detail.new({roads={paths={
        {width=4,points={{x=-200,z=0},{x=200,z=0}}},
        {width=8,points={{x=54,z=-10},{x=54,z=10}}},
        {width=4,points={{x=115,z=110},{x=120,z=115}}},
    }}})
    local transform={x=50,y=70,scale=1,rotation=0,centerX=0,centerZ=0}
    local roads=detail:visible(transform,{x=0,y=0,width=100,height=100})
    check('lan_minimap_culls_offscreen_detail_but_keeps_crossing_and_edge_roads',#roads==2)
    transform.rotation=math.pi/2
    roads=detail:visible(transform,{x=0,y=0,width=100,height=100})
    check('lan_minimap_culling_handles_rotated_offset_viewport',#roads==2)
end
return Test
