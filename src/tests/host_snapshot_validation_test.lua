local Test={}
function Test.run(check)
    local Schema=require('src.save_schema')
    local Home=require('src.home')
    local Town=require('src.commute.town')
    local Validation=require('src.net.host_snapshot_validation')
    local Session=require('src.net.session')
    local source=Schema.defaultState(assert(Home.new({town=assert(Town.generate(712345))})))
    local original=Town.copy(source.home.town)
    local handle=Validation.new()
    local valid,calls=Town.valid,0
    Town.valid=function(...)calls=calls+1;return valid(...)end
    local okay,err=xpcall(function()
        local first=assert(Schema.networkSnapshot(source,handle))
        check('host_snapshot_first_town_receives_full_validation',calls==1)
        calls=0
        local second=assert(Schema.networkSnapshot(source,handle))
        check('host_snapshot_unchanged_town_reuses_content_validation',calls==0)
        check('host_snapshot_results_and_cache_do_not_alias_mutable_source',
            first.home.town~=source.home.town and second.home.town~=first.home.town)
        first.home.town.size=1;first.home.town.terrain.heights[2000]=math.huge
        check('host_snapshot_result_mutation_cannot_poison_cached_town',
            Schema.networkSnapshot(source,handle)~=nil and calls==0)

        local mutations={
            {'size',function(t)t.size=1 end},
            {'terrain',function(t)t.terrain.heights[2000]=math.huge end},
            {'nan',function(t)t.terrain.heights[2000]=0/0 end},
            {'road',function(t)t.roads[1].points[1][1]=100000 end},
            {'destination',function(t)t.destinations.warehouse.x=-100 end},
            {'driving_map',function(t)t.drivingMap.version=-1 end},
            {'array_key',function(t)t.terrain.heights.extra=true end},
            {'function',function(t)t.hidden=function()end end},
            {'cycle',function(t)t.hidden=t end},
            {'missing_key',function(t)t.terrain.heights[2000]=nil end},
            {'extra_depth',function(t)local p=t;for _=1,20 do p.hidden={};p=p.hidden end end},
        }
        for _,mutation in ipairs(mutations) do
            source.home.town=Town.copy(original)
            mutation[2](source.home.town);calls=0
            check('host_snapshot_revalidates_in_place_'..mutation[1],
                Schema.networkSnapshot(source,handle)==nil and calls==1)
            source.home.town=Town.copy(original);calls=0
            check('host_snapshot_invalid_'..mutation[1]..'_does_not_replace_cache',
                Schema.networkSnapshot(source,handle)~=nil and calls==0)
        end

        source.home.town.name='Reviewed Town';calls=0
        check('host_snapshot_valid_nested_mutation_refreshes_cache',
            Schema.networkSnapshot(source,handle)~=nil and calls==1)
        calls=0;assert(Schema.networkSnapshot(source,handle))
        check('host_snapshot_valid_mutation_then_stabilizes',calls==0)
        source.home.town=Town.copy(original);calls=0
        check('host_snapshot_retains_only_one_prior_town',
            Schema.networkSnapshot(source,handle)~=nil and calls==1)
        source.home.town=Town.copy(original);calls=0
        check('host_snapshot_equal_detached_replacement_requires_no_geometric_validation',
            Schema.networkSnapshot(source,handle)~=nil and calls==0)

        local balance=source.home.balanceCents;source.home.balanceCents=-1;calls=0
        check('host_snapshot_cached_town_never_skips_other_household_validation',
            Schema.networkSnapshot(source,handle)==nil and calls==0)
        source.home.balanceCents=balance
        local eqCalls=0
        setmetatable(source.home.town.roads[1],{__eq=function()eqCalls=eqCalls+1;return true end})
        calls=0;assert(Schema.networkSnapshot(source,handle));assert(Schema.networkSnapshot(source,handle))
        check('host_snapshot_metatable_never_uses_fast_path_or_equality_override',calls==2 and eqCalls==0)
        setmetatable(source.home.town.roads[1],nil)

        source.home.town.size=1
        local forged={towns={[source.home.town]=true}}
        calls=0
        check('host_snapshot_forged_handle_never_authorizes_mutated_town',
            Schema.networkSnapshot(source,forged)==nil and calls==1)
        check('host_snapshot_direct_save_api_ignores_network_handle',Schema.snapshot(source,handle)==nil)
        check('host_snapshot_direct_valid_state_ignores_network_handle',not Schema.validState(source,handle))
        check('host_snapshot_default_home_normalization_still_revalidates',Home.normalize(source.home)==nil)
        source.home.town=Town.copy(original)
        calls=0;assert(Schema.snapshot(source));assert(Schema.snapshot(source))
        check('host_snapshot_ordinary_save_snapshots_keep_full_validation',calls==2)

        local session=Session.new();session.hostSnapshotValidation=handle;session:_resetRuntime()
        check('host_snapshot_session_reset_releases_private_handle',session.hostSnapshotValidation==nil)
        calls=0;assert(Schema.networkSnapshot(source,Validation.new()))
        check('host_snapshot_new_session_cannot_inherit_old_town_trust',calls==1)
        calls=0;assert(Schema.networkSnapshot(source,nil))
        check('host_snapshot_missing_handle_uses_normal_validation',calls==1)
    end,debug.traceback)
    Town.valid=valid
    assert(okay,err)
end
return Test
