local Test={}
function Test.run(check)
    local State=require('src.state')
    local Schema=require('src.save_schema')
    local Session=require('src.net.session')
    local Replication=require('src.net.shop_replication')
    local Shared=require('src.net.shared_validation')
    local Town=require('src.commute.town')
    local source=assert(Schema.snapshot(State.new()))
    local session=Session.new()
    session.mode='client';session.sessionId='validated-town';session.localId=2
    session:_installRoster({{id=2,x=100,y=100}},0)
    assert(session:_acceptInitialShopSnapshot({sessionId=session.sessionId,revision=1,state=source,player={x=100,y=100}}))
    local function event(kind)
        for _,item in ipairs(session:drainEvents())do if item.type==kind then return item end end
        error('missing '..kind)
    end
    local ready=event('ready')
    local guest=State.new()
    assert(State.applySharedSnapshot(guest,ready.state,ready.validation))
    local town=source.home.town
    check('lan_validation_memo_is_internal_and_does_not_alias_runtime_town',
        Shared.context(ready.validation)~=nil and source.validation==nil and guest.home.town~=town)
    local valid,calls=Town.valid,0
    Town.valid=function(...)calls=calls+1;return valid(...)end
    local okay,err=xpcall(function()
        for i=1,8 do
            assert(session:_acceptShopState({sessionId=session.sessionId,baseRevision=i,revision=i+1,state={
                {path={'home','revision'},value=i},{path={'money'},value=source.money+i}}}))
            local update=event('shop_state')
            assert(State.applySharedUpdate(guest,update.state,update.changed,update.validation))
        end
        check('lan_unchanged_private_replication_town_is_not_revalidated_per_delta',calls==0,'town validations='..calls)
        check('lan_replication_deltas_keep_prior_baseline_immutable',source.home.revision==0
            and session.receivedShop.home.revision==8 and session.receivedShop.home.town==town)

        guest.home.town.size=1
        check('lan_runtime_mutation_cannot_poison_private_validated_baseline',town.size==512 and not Schema.validState(guest))
        assert(session:_acceptShopState({sessionId=session.sessionId,baseRevision=9,revision=10,
            state={{path={'home','revision'},value=9}}}))
        local update=event('shop_state')
        assert(State.applySharedUpdate(guest,update.state,update.changed,update.validation))
        check('lan_private_baseline_restores_locally_mutated_runtime_copy',guest.home.town.size==512 and guest.home.town~=town)

        calls=0
        local replaced=Replication.apply(session.receivedShop,{{path={'home','town','size'},value=1}})
        check('lan_town_patch_clones_ancestors_before_validation',replaced.home.town~=town
            and replaced.home~=session.receivedShop.home and town.size==512)
        check('lan_invalid_nested_town_patch_cannot_reuse_validated_identity',
            not State.applySharedUpdate(guest,replaced,{home=true},ready.validation) and calls==1)
        local invalid=Replication.copy(session.receivedShop)
        invalid.home.town.size=1
        local forged={towns={[invalid.home.town]=true}}
        check('lan_forged_validation_metadata_cannot_skip_town_validation',
            Shared.context(forged)==nil and not State.applySharedUpdate(guest,invalid,{home=true},forged))
        check('lan_named_town_identity_does_not_authorize_invalid_replacement',
            invalid.home.town.id==town.id and not State.applySharedUpdate(guest,invalid,{home=true},ready.validation))

        local direct=Replication.copy(session.receivedShop)
        assert(State.applySharedUpdate(guest,direct,{home=true}))
        direct.home.town.size=1
        check('lan_direct_shared_update_revalidates_in_place_mutations',not State.applySharedUpdate(guest,direct,{home=true}))
        check('lan_normal_save_validation_never_uses_network_memo',not Schema.validState(direct,ready.validation))

        calls=0
        local replacedValid=Replication.copy(session.receivedShop)
        assert(State.applySharedUpdate(guest,replacedValid,{home=true},ready.validation))
        check('lan_new_town_object_receives_full_validation',calls==1)
        calls=0
        local nextSession=Session.new()
        nextSession.mode='client';nextSession.sessionId='next-town';nextSession.localId=2
        nextSession:_installRoster({{id=2,x=100,y=100}},0)
        assert(nextSession:_acceptInitialShopSnapshot({sessionId='next-town',revision=1,state=session.receivedShop,player={x=100,y=100}}))
        local nextReady
        for _,item in ipairs(nextSession:drainEvents())do if item.type=='ready' then nextReady=item end end
        assert(Schema.validSharedState(nextReady.state,nextReady.validation))
        check('lan_validation_memo_is_not_shared_across_sessions',nextReady.validation~=ready.validation and calls==1)
        session:_resetRuntime()
        check('lan_session_reset_releases_town_validation_memo',session.sharedValidation==nil)
        local memo=Shared.context(ready.validation).towns
        check('lan_replaced_towns_are_not_retained_by_validation_memo',getmetatable(memo).__mode=='k')
    end,debug.traceback)
    Town.valid=valid
    assert(okay,err)
end
return Test
