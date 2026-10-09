-- Starting shops and saving authoritative state.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.saveCurrent()
        if Runtime.multiplayer:isClient() then return false end
        if not Runtime.state.activeSlot then return false end
        local saved = Runtime.Save.save(Runtime.state.activeSlot, Runtime.state, Runtime.World.snapshot())
        if saved and Runtime.multiplayer:isHost() then Runtime.multiplayer:markShopDirty(true) end
        return saved
    end

    function Runtime.startGame(payload, mode)
        local applied, windmillSanitized = Runtime.State.applyLocalSave(Runtime.state, payload)
        if not applied then return false, "That shop save could not be opened safely." end
        Runtime.App.gameClockSpeed = 1
        Runtime.App.gameClockSyncClock = 0
        Runtime.App.gameClockSaveClock = 0
        Runtime.World.load(payload.player)
        require("src.air_hockey").clear()
        require("src.basketball").clear()
        require("src.critter_kombat").clear()
        Runtime.App.syncPlayerColorways()
        Runtime.Machine.reset()
        Runtime.Wrapper.clearInstances()
        Runtime.Windmill.resetNetworkRuntime()
        Runtime.activeCutterRemote = nil
        Runtime.activeWrapperRemote = nil
        Runtime.activeWindmillRemote = nil
        Runtime.machineRemoteSessions = {}
        if (mode == "new" or windmillSanitized) and not Runtime.saveCurrent() then
            return false, mode == "new"
                and "This device could not create the new shop save."
                or "This device could not save the safely stopped Windmill state."
        end
        if payload.recovered then
            Runtime.state.message = "Recovered this shop from its last valid " .. tostring(payload.recoverySource) .. " copy."
        end
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
