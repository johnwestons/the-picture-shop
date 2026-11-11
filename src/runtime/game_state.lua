-- Starting shops and saving authoritative state.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    local checkpoint = require("src.save_checkpoint").new(5)
    local saveFailureMessage
    function Runtime.saveCurrent(immediate)
        if Runtime.multiplayer:isClient() then return false,"multiplayer_client" end
        if not Runtime.state.activeSlot then return false,"no_active_slot" end
        local saved,reason = Runtime.Save.queue(Runtime.state.activeSlot, Runtime.state, Runtime.World.snapshot())
        if saved and immediate then saved,reason=Runtime.Save.flush() end
        if saved and immediate and saveFailureMessage then
            if Runtime.state.message==saveFailureMessage then Runtime.state.message=nil end
            saveFailureMessage=nil
        end
        if saved then checkpoint:reset() end
        if saved and Runtime.multiplayer:isHost() then Runtime.multiplayer:markShopDirty(true) end
        return saved,reason
    end

    function Runtime.pollSaves()
        for _,result in ipairs(Runtime.Save.poll()) do
            if result.slot==Runtime.state.activeSlot
                and result.directory==love.filesystem.getSaveDirectory() then
                if not result.okay then
                    checkpoint.pending=true
                    local detail=result.reason and tostring(result.reason):gsub("[%c]+"," "):sub(1,120)
                    saveFailureMessage="The shop could not be saved. Retrying shortly."
                        ..(detail and detail~="" and (" ("..detail..")") or "")
                    Runtime.state.message=saveFailureMessage
                else
                    if saveFailureMessage and Runtime.state.message==saveFailureMessage then
                        Runtime.state.message=nil
                    end
                    saveFailureMessage=nil
                end
            end
        end
    end

    function Runtime.updateCheckpoint(dt, dirty)
        if Runtime.multiplayer:isClient() or not Runtime.state.activeSlot then
            checkpoint:reset()
            return false
        end
        return checkpoint:update(dt,dirty,Runtime.saveCurrent)
    end

    function Runtime.startGame(payload, mode)
        Runtime._storyOpening=nil
        -- Pending coalesced requests still refer to the current live shop.
        -- Finish them before reusing that state table for another save slot.
        if Runtime.Save.flush and not Runtime.Save.flush() then
            return false,"The previous shop could not be saved. Please try again."
        end
        local applied, windmillSanitized = Runtime.State.applyLocalSave(Runtime.state, payload)
        if not applied then return false, "That shop save could not be opened safely." end
        require('src.ai_watchdog').reset(Runtime.state)
        checkpoint:reset()
        Runtime.App.gameClockSpeed = 1
        Runtime.App.gameClockSyncClock = 0
        Runtime.App.gameClockSaveClock = 0
        Runtime.World.load(payload.player)
        require('src.commute.runtime').release(Runtime)
        Runtime._weekendScene,Runtime._weekendPromptToken=nil,nil
        local week=require("src.weekend_flow").ensure(Runtime.state)
        require("src.home_residents").recover(Runtime.state)
        Runtime.World.player.homeResidentId="owner";Runtime.World.player.homeJoinedAtHours=nil
        require("src.home_travel").clearRequest(week)
        if mode=="new" and Runtime.state.warehouse.condition.mode=="story" then
            local spawned,reason=require('src.story_intro').spawn(Runtime)
            if not spawned then return false,"Could not start at Grandpa's farm: "..tostring(reason) end
        end
        if Runtime.state.home.commute then
            require('src.commute.runtime').restore(Runtime)
        elseif require("src.weekend_flow").atHome(Runtime.state) then
            Runtime.World.player.sceneId="home"
            if not payload.player or payload.player.sceneId~="home" then
                Runtime.World.player.x,Runtime.World.player.y=require("src.home_layouts").spawn(Runtime.state,1)
            end
        end
        require('src.story_progress').reconcile(Runtime)
        if Runtime.World.player.sceneId=="home" then
            local rooms=require("src.shop_rooms")
            local assets=rooms.assets(Runtime.Assets,"home",Runtime.state)
            local p=Runtime.World.player
            if not require("src.navigation").isWalkable(assets,p.x,p.y,{}) then
                p.x,p.y=require("src.home_layouts").spawn(Runtime.state,1)
            end
        end
        require("src.air_hockey").clear()
        require("src.basketball").clear()
        require("src.basketball_controls").clear(Runtime)
        require("src.critter_kombat").clear()
        require("src.critter_crisis").clear()
        Runtime.App.syncPlayerColorways()
        Runtime.Machine.reset()
        Runtime.Wrapper.clearInstances()
        Runtime.Windmill.resetNetworkRuntime()
        Runtime.activeCutterRemote = nil
        Runtime.activeWrapperRemote = nil
        Runtime.activeWindmillRemote = nil
        Runtime.machineRemoteSessions = {}
        if (mode == "new" or windmillSanitized) and not Runtime.saveCurrent(true) then
            return false, mode == "new"
                and "This device could not create the new shop save."
                or "This device could not save the safely stopped Windmill state."
        end
        local imported,amount=require('src.portable_pay').claim(Runtime.state,Runtime.Save,Runtime.saveCurrent)
        if not imported then return false,'Portable wages could not be imported: '..tostring(amount) end
        if amount>0 then
            Runtime.state.message=string.format('Transferred $%.2f in wages from hosted shops to your household.',amount/100)
        end
        if payload.recovered then
            Runtime.state.message = "Recovered this shop from its last valid " .. tostring(payload.recoverySource) .. " copy."
        end
        require('src.story_opening').begin(Runtime)
        return true
    end

    Runtime.returnToTitle = nil
    Runtime.openLocalPlay = nil
    Runtime.openDirectPlay = nil
    Runtime.openDirectInvite = nil
    Runtime.closeDirectConnection = nil
    Runtime.closeDirectHostComposite = nil
    Runtime.syncMobileKeyboard = nil
    Runtime.openOptions = nil
end

return Component
