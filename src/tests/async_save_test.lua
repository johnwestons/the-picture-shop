local Test={}
function Test.run(context,check)
    local save=require("src.save")
    local state=context.State.new()
    local slot=3
    save.delete(slot)
    state.money=123
    assert(save.queue(slot,state,{x=100,y=250}))
    state.money=999
    assert(save.flush())
    check("async_save_worker_commits_detached_snapshot",save.load(slot).state.money==123)
    for index=1,20 do
        state.money=1000+index
        assert(save.queue(slot,state,{x=100,y=250}))
    end
    assert(save.flush())
    check("async_save_coalesces_to_latest_request",save.load(slot).state.money==1020 and not save.pending())
    state.money=2020
    assert(save.queue(slot,state,{x=100,y=250}))
    assert(save.flush())
    love.filesystem.write("saves/slot3.lua","{")
    local recovered,status=save.load(slot)
    check("async_save_keeps_verified_recovery_copy",status=="recovered" and recovered.state.money==1020)
    assert(save.queue(slot,state,{x=100,y=250}))
    assert(save.delete(slot))
    love.timer.sleep(.01)
    check("async_save_delete_cannot_be_resurrected_by_worker",save.load(slot)==nil and not save.pending())
    local identity=love.filesystem.getIdentity()
    state.money=3030
    assert(save.queue(slot,state,{x=100,y=250}))
    love.filesystem.setIdentity(identity.."-other")
    local okay,reason=save.flush()
    local absent=love.filesystem.getInfo("saves/slot3.lua")==nil
    love.filesystem.setIdentity(identity)
    assert(okay,reason)
    check("async_save_is_pinned_to_original_profile",absent and save.load(slot).state.money==3030)
    love.filesystem.createDirectory("saves/slot3.lua.tmp")
    love.filesystem.write("saves/slot3.lua.tmp/blocker","test")
    assert(save.queue(slot,state,{x=100,y=250}))
    local diskOkay=save.flush()
    love.filesystem.remove("saves/slot3.lua.tmp/blocker")
    love.filesystem.remove("saves/slot3.lua.tmp")
    check("async_save_disk_failure_preserves_primary",not diskOkay and save.load(slot).state.money==3030)
    state.money=4040
    assert(save.queue(slot,state,{x=100,y=250}));assert(save.flush())
    check("async_save_can_retry_after_disk_failure",save.load(slot).state.money==4040)
    assert(save.queue(slot,{jobs={active="invalid"}},{x=100,y=250}))
    local accepted=save.flush()
    check("async_save_rejects_invalid_snapshot_without_replacing_primary",
        not accepted and save.load(slot).state.money==4040)
    local hostChanges=0
    local runtime={App={},state=context.State.new(),Save=save,
        multiplayer={isClient=function() return false end,isHost=function() return true end,
            markShopDirty=function() hostChanges=hostChanges+1 end},
        World={snapshot=function() return {x=100,y=250} end}}
    runtime.state.activeSlot=slot
    require("src.runtime.game_state").install(runtime)
    runtime.state.money=5050
    assert(runtime.saveCurrent())
    check("async_runtime_publishes_host_change_without_waiting_for_disk",save.pending() and hostChanges==1)
    runtime.state.money=6060
    assert(runtime.saveCurrent(true))
    check("async_runtime_lifecycle_flush_writes_latest_shop",not save.pending() and save.load(slot).state.money==6060)
    save.delete(slot)
    assert(save.shutdown())
end
return Test
