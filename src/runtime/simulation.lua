-- Background sessions and game simulation updates.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.serviceNetworkBeforeMachine = function(dt, targetState, networkService, windmillService)
        networkService()
        local machineDurable = Runtime.Machine.updateAll(dt, targetState)
        local windmillChanged, windmillDurable = false, false
        if windmillService then
            windmillChanged, windmillDurable = windmillService(dt, targetState)
        end
        return machineDurable or windmillDurable, windmillChanged, windmillDurable
    end

    function Runtime.App.closeBackgroundHostSession(reason)
        Runtime.saveCurrent()
        Runtime.lanDiscovery:stop()
        Runtime.lanReconnect:cancel(true)
        Runtime.lanReconnectArmed = false

        local sessionClean, sessionError = Runtime.multiplayer:stop(reason)
        Runtime.clearWorkshopAuthority("host_background_timeout")
        local connectionClean, connectionError = Runtime.closeDirectConnection()
        local hostClean, hostError = Runtime.closeDirectHostComposite()
        if not sessionClean or not connectionClean or not hostClean then
            return false, sessionError or connectionError or hostError
        end

        Runtime.DirectScreen.leave()
        if Runtime.state.screen == "direct" then Runtime.state.screen = "world" end
        Runtime.state.message = "Multiplayer ended because the game stayed in the background for more than 2 minutes."
        if Runtime.isAndroidPlatform() and love.window and love.window.setDisplaySleepEnabled then
            love.window.setDisplaySleepEnabled(true)
        end
        return true
    end

    function Runtime.App.expireBackgroundMultiplayer()
        if not Runtime.multiplayer:isActive() then return false end
        local networkKind = Runtime.multiplayer.networkKind
        local hostSession = Runtime.multiplayer:isHost()
        local reason = "Game stayed in the background for more than 2 minutes"
        local message = "Multiplayer ended because the game stayed in the background for more than 2 minutes."

        if not hostSession then
            Runtime.lanReconnect:cancel(true)
            Runtime.lanReconnectArmed = false
            Runtime.WorkshopRemoteScreen.clear()
            Runtime.MultiplayerHud.reset()
            Runtime.showConnectionError(message, reason)
            return true
        end

        local closed, cleanupError = Runtime.App.closeBackgroundHostSession(reason)
        if not closed then
            if networkKind == "direct" then
                Runtime.enterDirectCleanupScreen(cleanupError, function()
                    return Runtime.App.closeBackgroundHostSession(reason)
                end)
            else
                Runtime.state.screen = "lan"
                Runtime.LanScreen.showError(cleanupError)
            end
        end
        return true
    end

    function Runtime.App.update(dt)
        Runtime.Assets.pruneCache()
        Runtime.CharacterAssets.pruneCache()
        Runtime.WorldRenderer.pruneCache()
        require("src.jukebox").update(Runtime.state.screen ~= "title" and Runtime.state.screen ~= "asset_error",
            Runtime.multiplayer:isClient())
        require("src.jukebox").syncMultiplayer(Runtime.multiplayer)
        if Runtime.App.multiplayerFocusGrace:isExpired() then
            Runtime.App.multiplayerFocusGrace:clear()
            Runtime.App.expireBackgroundMultiplayer()
        end
        Runtime.App.syncPlayerColorways()
        Runtime.syncCamera()
        if Runtime.controller then Runtime.controller:update(dt) end
        if Runtime.spriteLabActive then Runtime.SpriteMotionLab.update(dt, Runtime.CharacterAssets); return end
        Runtime.DirectIpv4Runtime.updateHosts()
        Runtime.DirectIpv4Runtime.updateConnection()
        Runtime.updateLanConvenience(dt)
        Runtime.Machine.setMultiplayerSingleControl(Runtime.multiplayer:isActive())
        local saveNeeded = false
        local networkInputX, networkInputY = 0, 0
        Runtime.airHockeyInputX,Runtime.airHockeyInputY=0,0
        Runtime.kombatInputX,Runtime.kombatButtons=0,0
        local predictedJackOwner
        if Runtime.state.screen ~= "world" and Runtime.PalletJack.isOperator(
            Runtime.state, Runtime.Config.palletJack, Runtime.World.player.id or 1) then
            Runtime.PalletJack.stop(Runtime.state, Runtime.Config.palletJack)
        end
        local simulationScreen = Runtime.state.screen == "options" and Runtime.state.optionsReturnScreen
            or Runtime.state.screen
        local simulationActive = simulationScreen ~= "title"
            and simulationScreen ~= "lan" and simulationScreen ~= "direct"
            and simulationScreen ~= "asset_error"
        local gameDt = dt
        if not Runtime.multiplayer:isClient() and simulationActive then
            gameDt = dt * (Runtime.App.gameClockSpeed or 1)
        end
        if Runtime.multiplayer:isHost() and simulationActive and Runtime.App.gameClockSpeed > 1 then
            Runtime.App.gameClockSyncClock = Runtime.App.gameClockSyncClock + dt
            if Runtime.App.gameClockSyncClock >= 0.25 then
                Runtime.App.gameClockSyncClock = Runtime.App.gameClockSyncClock % 0.25
                Runtime.multiplayer:markShopDirty()
            end
        else
            Runtime.App.gameClockSyncClock = 0
        end
        if not Runtime.multiplayer:isClient() and simulationActive and Runtime.App.gameClockSpeed > 1 then
            Runtime.App.gameClockSaveClock = Runtime.App.gameClockSaveClock + dt
            if Runtime.App.gameClockSaveClock >= 5 then
                Runtime.App.gameClockSaveClock = Runtime.App.gameClockSaveClock % 5
                saveNeeded = true
            end
        else
            Runtime.App.gameClockSaveClock = 0
        end
        if not Runtime.multiplayer:isClient() and simulationActive then
            local calendarChanged = Runtime.BusinessCalendar.update(Runtime.state, gameDt)
            local emailArrived = Runtime.JobService.updateClientEmails(Runtime.state)
            local technicianChanged = Runtime.MachineMaintenance.updateTechnician(Runtime.state)
            if Runtime.state.screen~="world" and Runtime.state.forklift and Runtime.state.forklift.operating
                and Runtime.state.forklift.operatorPlayerId==1 then
                Runtime.World.updateNetworkForklift(Runtime.World.player,0,0,0,Runtime.Assets,Runtime.state)
            end
            local warehouseChanged=Runtime.World.updateWarehouse(gameDt,Runtime.state,Runtime.Assets)
            local phoneChanged = Runtime.WorkPhone.update(Runtime.state)
            if calendarChanged or emailArrived or technicianChanged or phoneChanged then saveNeeded = true end
            Runtime.warehouseSaveClock=Runtime.warehouseSaveClock+dt
            if warehouseChanged and Runtime.multiplayer:isHost() then Runtime.multiplayer:markShopDirty() end
            if Runtime.warehouseSaveClock>=1 and (warehouseChanged or Runtime.state.constructionWorker) then
                saveNeeded = true; Runtime.warehouseSaveClock=0
            end
        end
        if Runtime.state.screen == "asset_error" then
            return
        elseif Runtime.state.screen == "title" then
            Runtime.TitleScreen.update(dt)
        elseif Runtime.state.screen == "lan" then
            Runtime.LanScreen.update(dt)
        elseif Runtime.state.screen == "direct" then
            Runtime.DirectScreen.update(dt)
        elseif Runtime.state.screen == "world" then
            local directionX, directionY = Runtime.Input.movement()
            if require("src.basketball").isChargingFor(Runtime.state,
                tonumber(Runtime.World.player.id) or 1) then
                directionX,directionY=0,0
            end
            networkInputX, networkInputY = directionX, directionY
            if Runtime.multiplayer:isClient() then
                local cursorX, cursorY
                if not (Runtime.controller and Runtime.controller:isActive()) then
                    cursorX, cursorY = Runtime.pointerPosition()
                    if Runtime.App.cameraTransformsWorld() then
                        cursorX, cursorY = Runtime.App.mobileCamera:screenToWorld(cursorX, cursorY)
                    end
                end
                local workshopInfo = Runtime.multiplayer:workshopInfo()
                local jack = Runtime.PalletJack.ensure(Runtime.state, Runtime.Config.palletJack)
                local controlsJack = workshopInfo
                    and workshopInfo.resourceId == "pallet_jack"
                    and jack.operatorPlayerId == Runtime.World.player.id
                if controlsJack then
                    predictedJackOwner = jack.operatorPlayerId
                    Runtime.World.updateNetworkPalletJack(
                        Runtime.World.player, dt, directionX, directionY,
                        Runtime.Assets, Runtime.state, cursorX, cursorY)
                else
                    Runtime.World.updateNetworkPlayer(
                        dt, directionX, directionY, Runtime.Assets, Runtime.state, cursorX, cursorY)
                end
            else
                local cursorX, cursorY
                if not (Runtime.controller and Runtime.controller:isActive()) then
                    cursorX, cursorY = Runtime.pointerPosition()
                    if Runtime.App.cameraTransformsWorld() then
                        cursorX, cursorY = Runtime.App.mobileCamera:screenToWorld(cursorX, cursorY)
                    end
                end
                if Runtime.World.update(dt, directionX, directionY, Runtime.Assets, Runtime.state, cursorX, cursorY, gameDt) then saveNeeded = true end
            end
        elseif Runtime.state.screen == "air_hockey" then
            local keyX,keyY=Runtime.Input.movement()
            Runtime.airHockeyInputX,Runtime.airHockeyInputY=
                require("src.screens.air_hockey_screen").controls(Runtime,keyX,keyY)
        elseif Runtime.state.screen == "critter_kombat" then
            Runtime.kombatInputX,Runtime.kombatButtons=
                require("src.screens.critter_kombat_screen").controls(Runtime)
        elseif Runtime.state.screen == "machine" and not Runtime.multiplayer:isClient() then
            Runtime.MachineScreen.update(dt)
        elseif Runtime.state.screen == "press" and not Runtime.multiplayer:isClient() then
            Runtime.PressScreen.update(dt, Runtime.state)
        elseif Runtime.state.screen == "workshop_remote" then
            Runtime.WorkshopRemoteScreen.update(dt)
        end
        -- World events belong to the host simulation, not to its current screen.
        -- Guests may keep walking and working while the host reads any shop menu.
        if not Runtime.multiplayer:isClient() and simulationActive and Runtime.state.screen ~= "world" then
            if Runtime.World.updateSimulation(gameDt, Runtime.Assets, Runtime.state, dt) then saveNeeded = true end
        end
        if not Runtime.multiplayer:isClient() and simulationActive then
            local inputs={}
            local participants={}
            inputs[tonumber(Runtime.World.player.id) or 1]={x=Runtime.airHockeyInputX,y=Runtime.airHockeyInputY}
            participants[tonumber(Runtime.World.player.id) or 1]=Runtime.World.player
            for _,player in ipairs(Runtime.multiplayer.remotePlayers
                and Runtime.multiplayer:remotePlayers() or {}) do
                local fresh=Runtime.multiplayer.clock()-(player.lastInputAt or 0)<=.35
                inputs[player.id]={x=fresh and (player.gameInputX or 0) or 0,
                    y=fresh and (player.gameInputY or 0) or 0}
                participants[player.id]=player
            end
            local hockey=require("src.air_hockey")
            hockey.prune(participants)
            hockey.update(dt,function(id) return inputs[id] end)
            if require("src.basketball").update(dt,Runtime.state,participants) then saveNeeded=true end
            local kombat=require("src.critter_kombat")
            kombat.prune(participants)
            kombat.update(dt,function(id)
                if id==(tonumber(Runtime.World.player.id) or 1) then
                    return {x=Runtime.kombatInputX,buttons=Runtime.kombatButtons}
                end
                local player=participants[id]
                if not player or Runtime.multiplayer.clock()-(player.lastInputAt or 0)>.35 then return nil end
                return {x=player.gameInputX or 0,buttons=player.combatButtons or 0}
            end)
        end
        local advanceAuthoritativeMachines = not Runtime.multiplayer:isClient() and simulationActive
        if advanceAuthoritativeMachines then
            if Runtime.serviceNetworkBeforeMachine(gameDt, Runtime.state, function()
                Runtime.updateMultiplayer(dt, networkInputX, networkInputY, predictedJackOwner)
            end, function(machineDt, targetState)
                return Runtime.Windmill.updateAll(machineDt, targetState)
            end) then
                saveNeeded = true
            end
        else
            Runtime.updateMultiplayer(dt, networkInputX, networkInputY, predictedJackOwner)
        end
        if not Runtime.multiplayer:isClient() and simulationActive and Runtime.Wrapper.updateAll(gameDt, Runtime.state)
        then
            saveNeeded = true
        end
        if not Runtime.multiplayer:isClient() and simulationActive and Runtime.state.employment
            and (#Runtime.state.employment.applications>0 or #Runtime.state.employment.staff>0) then
            Runtime.employmentSaveClock=Runtime.employmentSaveClock+dt
            if Runtime.employmentSaveClock>=1 then saveNeeded = true;Runtime.employmentSaveClock=0 end
        end
        if Runtime.App.sound then Runtime.App.sound:update(dt) end
        Runtime.syncCamera()
        if Runtime.App.mobileCamera then Runtime.App.mobileCamera:update(dt) end
        -- Commit the final frame once when several simulations change together.
        if saveNeeded then Runtime.saveCurrent() end
    end
end

return Component
