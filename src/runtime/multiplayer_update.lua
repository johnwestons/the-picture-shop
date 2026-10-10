-- Workshop requests and authoritative network updates.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}
local PlayerActivity = require("src.player_activity")

local function updateTaskVisual(player, action, dt, now)
    if not player then return end
    player.taskAction = action
    if player.taskClockAction ~= action then
        player.taskClockAction = action
        player.taskClock = 0
        player.taskClockUpdatedAt = now
    elseif action then
        local previous = player.taskClockUpdatedAt
        local elapsed = previous and math.max(0, math.min(0.25, now - previous)) or math.max(0, dt or 0)
        player.taskClock = (player.taskClock or 0) + elapsed
        player.taskClockUpdatedAt = now
    else
        player.taskClock = 0
        player.taskClockUpdatedAt = now
    end
end

function Component.install(Runtime)
    function Runtime.performWorkshopRequest(player, operation, payload)
        if not Runtime.workshopAuthority then
            return {
                accepted = false, code = "unavailable",
                message = "Workshop authority is unavailable on the host device.", revision = 0,
            }
        end
        if operation == "workshop_acquire" then
            local revision = Runtime.workshopAuthority:resourceRevision(payload.resourceId) or 0
            if payload.expectedRevision ~= revision then
                return {
                    accepted = false, code = "revision_conflict",
                    message = "That workshop changed; try the control again.", revision = revision,
                }
            end
            return Runtime.workshopAuthority:acquire(player, {
                requestId = payload.requestId,
                resourceId = payload.resourceId,
            }, { state = Runtime.state })
        elseif operation == "workshop_command" then
            local arguments = {}
            if payload.amount ~= nil then arguments.amount = payload.amount end
            if payload.callId ~= nil then arguments.callId = payload.callId end
            if payload.officeIntent ~= nil then arguments.officeIntent = payload.officeIntent end
            if payload.warehouseIntent ~= nil then arguments.warehouseIntent = payload.warehouseIntent end
            if payload.itemIndex ~= nil then arguments.itemIndex = payload.itemIndex end
            if payload.machineIndex ~= nil then arguments.machineIndex = payload.machineIndex end
            if payload.machineId ~= nil then arguments.machineId = payload.machineId end
            if payload.placementCell ~= nil then arguments.placementCell = payload.placementCell end
            if payload.jobId ~= nil then arguments.jobId = payload.jobId end
            if payload.palletId ~= nil then arguments.palletId = payload.palletId end
            if payload.plateId ~= nil then arguments.plateId = payload.plateId end
            if payload.setupTask ~= nil then arguments.setupTask = payload.setupTask end
            if payload.setupAction ~= nil then arguments.setupAction = payload.setupAction end
            if payload.programIndex ~= nil then arguments.programIndex = payload.programIndex end
            if payload.gaugeCentiInch ~= nil then
                arguments.gaugeCentiInch = payload.gaugeCentiInch
            end
            if payload.clamp ~= nil then arguments.clamp = payload.clamp end
            if payload.barrierClear ~= nil then arguments.barrierClear = payload.barrierClear end
            if payload.enabled ~= nil then arguments.enabled = payload.enabled end
            local result = Runtime.workshopAuthority:command(player, {
                requestId = payload.commandId,
                resourceId = payload.resourceId,
                leaseId = payload.leaseId,
                action = payload.action,
                args = arguments,
                expectedRevision = payload.expectedRevision,
            }, { state = Runtime.state })
            if Runtime.acceptanceHostPlan and payload.resourceId == "pallet_jack" then
                print(string.format(
                    "[ACCEPTANCE HOST] COMMAND action=%s accepted=%s code=%s cutter=%s wrapper=%s windmill=%s",
                    tostring(payload.action), tostring(result.accepted), tostring(result.code),
                    tostring(Runtime.state.cutter and Runtime.state.cutter.moving == true),
                    tostring(Runtime.state.wrapper and Runtime.state.wrapper.moving == true),
                    tostring(Runtime.state.windmill and Runtime.state.windmill.moving == true)))
                io.flush()
            end
            return result
        elseif operation == "workshop_release" then
            return Runtime.workshopAuthority:release(player, {
                requestId = payload.requestId,
                resourceId = payload.resourceId,
                leaseId = payload.leaseId,
                reason = payload.reason,
            }, { state = Runtime.state })
        end
        return {
            accepted = false, code = "not_allowed",
            message = "That workshop operation is not allowed.", revision = 0,
        }
    end

    function Runtime.updateMultiplayer(dt, inputX, inputY, predictedJackOwner)
        local now = love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
        local localPlayer = Runtime.World.player
        local localTaskAction = PlayerActivity.forState(
            Runtime.state, Runtime.WorkshopRemoteScreen, localPlayer)
        updateTaskVisual(localPlayer, localTaskAction, dt, now)
        if Runtime.multiplayer then Runtime.multiplayer.localTaskAction = localTaskAction or "none" end
        if not Runtime.multiplayer:isActive() then
            if localPlayer then localPlayer.highFiveAnimation = nil end
            return
        end
        if Runtime.multiplayer:isHost() then Runtime.registerInstalledMachineResources(Runtime.workshopAuthority) end
        if Runtime.workshopAuthority and Runtime.localWorkshopLease then
            Runtime.workshopAuthority:touchPlayer(Runtime.localAuthorityPlayer())
        end
        Runtime.multiplayer:update(dt, {
            localPlayer = localPlayer,
            inputX = inputX or 0,
            inputY = inputY or 0,
            gameX = Runtime.basketballCharge and Runtime.basketballCharge.aimX/100
                or (Runtime.airHockeyInputX or 0)+(Runtime.kombatInputX or 0),
            gameY = Runtime.basketballCharge and (Runtime.basketballCharge.arcHeight-105)/85
                or Runtime.airHockeyInputY or 0,
            combatButtons = Runtime.kombatButtons or 0,
            moveRemote = function(player, moveDt, moveX, moveY)
                if require("src.basketball").isCharging(player.id) then moveX,moveY=0,0 end
                Runtime.World.updateRemotePlayer(player, moveDt, moveX, moveY, Runtime.Assets, Runtime.state)
            end,
            resolveGuestSpawn = function(hostX, hostY, guestIndex, players)
                if require("src.shop_rooms").scene(Runtime.World.player)~="warehouse" then
                    hostX,hostY=Runtime.Config.player.spawnX,Runtime.Config.player.spawnY
                end
                return Runtime.World.resolveNetworkSpawn(hostX, hostY, guestIndex, Runtime.Assets, Runtime.state, players)
            end,
            getShopSnapshot = function()
                return {
                    state = Runtime.SaveSchema.snapshot(Runtime.state),
                    player = Runtime.World.snapshot(),
                }
            end,
            getVisitorSnapshot = function()
                return {
                    customer = Runtime.World.customerSnapshot(),
                    vendor = Runtime.World.vendorSnapshot(),
                }
            end,
            getGameSnapshot = function()
                return require("src.air_hockey").snapshot()
            end,
            getBasketballSnapshot = function()
                return require("src.basketball").snapshot(Runtime.state)
            end,
            getFightSnapshot = function()
                return require("src.critter_kombat").snapshot()
            end,
            getEnvironmentSnapshot = function()
                return Runtime.World.environmentSnapshot()
            end,
            getPalletJackSnapshot = function()
                return Runtime.World.networkPalletJackSnapshot(Runtime.state)
            end,
            getForkliftSnapshot=function() return Runtime.Forklift.snapshot(Runtime.state,Runtime.Config.forklift) end,
            getMachinePoseSnapshot = function()
                return Runtime.World.networkMachinePoseSnapshot(Runtime.state)
            end,
            getWorkshopSnapshot = function()
                return {
                    resources = Runtime.workshopAuthority and Runtime.workshopAuthority:snapshot() or {},
                    wrapper = Runtime.wrapperSnapshotView(),
                }
            end,
            getCutterSnapshot = function()
                local snapshots = {}
                for _, unit in ipairs(Runtime.MachineFleet.installedUnits(Runtime.state, "polar_115")) do
                    local resourceId = Runtime.MachineResource.forUnit("cutter", unit.id)
                    snapshots[#snapshots + 1] = {
                        resourceId = resourceId,
                        resourceRevision = Runtime.workshopAuthority
                            and Runtime.workshopAuthority:resourceRevision(resourceId) or 0,
                        view = Runtime.withWorkshopUnit("cutter", unit.id, resourceId, function()
                            return Runtime.cutterMaintenanceAuthority.view(
                                Runtime.machineRemoteSessions[resourceId], true)
                        end),
                    }
                end
                return snapshots
            end,
            getWindmillSnapshot = function()
                local snapshots = {}
                for _, unit in ipairs(Runtime.MachineFleet.installedUnits(Runtime.state, "heidelberg_10x15")) do
                    local resourceId = Runtime.MachineResource.forUnit("windmill", unit.id)
                    snapshots[#snapshots + 1] = {
                        resourceId = resourceId,
                        resourceRevision = Runtime.workshopAuthority
                            and Runtime.workshopAuthority:resourceRevision(resourceId) or 0,
                        view = Runtime.withWorkshopUnit("windmill", unit.id, resourceId, function()
                            return Runtime.windmillView(Runtime.machineRemoteSessions[resourceId])
                        end),
                    }
                end
                return snapshots
            end,
            getWrapperSnapshots = function()
                local snapshots = {}
                for _, unit in ipairs(Runtime.MachineFleet.installedUnits(Runtime.state, "skid_wrapper")) do
                    local resourceId = Runtime.MachineResource.forUnit("skid_wrapper", unit.id)
                    snapshots[#snapshots + 1] = {
                        resourceId = resourceId,
                        resourceRevision = Runtime.workshopAuthority
                            and Runtime.workshopAuthority:resourceRevision(resourceId) or 0,
                        view = Runtime.withWorkshopUnit("skid_wrapper", unit.id, resourceId, function()
                            return Runtime.wrapperMaintenanceAuthority.view(
                                Runtime.machineRemoteSessions[resourceId], false)
                        end),
                    }
                end
                return snapshots
            end,
            performWorkshop = Runtime.performWorkshopRequest,
            touchWorkshop = function(player)
                if Runtime.workshopAuthority then Runtime.workshopAuthority:touchPlayer(player) end
            end,
            updateWorkshop = function()
                if not Runtime.workshopAuthority then return end
                local events = Runtime.workshopAuthority:update({ state = Runtime.state })
                for _, event in ipairs(events) do
                    if Runtime.localWorkshopLease and event.leaseId == Runtime.localWorkshopLease.leaseId then
                        Runtime.localWorkshopLease = nil
                    end
                end
            end,
            performInteraction = function(player, targetKind, desiredState, shotAim)
                local okay,code,message,kind=Runtime.World.performNetworkInteraction(player, Runtime.state, targetKind, desiredState,shotAim)
                if okay and targetKind=="roomStock" and code=="accepted" then Runtime.saveCurrent() end
                if okay and targetKind=="roomGame" and
                    (desiredState=="basketball:pickup" or desiredState=="basketball:drop") then
                    Runtime.saveCurrent()
                end
                return okay,code,message,kind
            end,
            getRadioSnapshot = function()
                return require("src.jukebox").networkState()
            end,
        })
        Runtime.state._networkBasketballs=Runtime.multiplayer:isClient()
            and Runtime.multiplayer:ballSnapshot() or nil
        if Runtime.World.player then
            Runtime.World.player.highFiveAnimation = Runtime.multiplayer:highFiveAnimationFor(
                Runtime.World.player.id or 1)
        end
        for _, player in ipairs(Runtime.multiplayer:remotePlayers()) do
            player.highFiveAnimation = Runtime.multiplayer:highFiveAnimationFor(player.id)
        end
        Runtime.handleMultiplayerEvents()
        local leasedActions = {}
        if Runtime.workshopAuthority then
            for _, resource in ipairs(Runtime.workshopAuthority:snapshot()) do
                local ownerId = tonumber(resource.ownerPlayerId)
                local action = PlayerActivity.resourceAction(resource.resourceId)
                if ownerId and action then leasedActions[ownerId] = action end
            end
        end
        for _, player in ipairs(Runtime.multiplayer:remotePlayers()) do
            local action = player.taskAction or leasedActions[tonumber(player.id)]
            local forklift = Runtime.state.forklift
            if not action and forklift and forklift.operating == true
                and tonumber(forklift.operatorPlayerId) == tonumber(player.id) then
                action = "operate_forklift"
            end
            updateTaskVisual(player, action, dt, now)
        end
        if Runtime.acceptanceHostPlan and Runtime.multiplayer:isHost() then
            local jack = Runtime.PalletJack.ensure(Runtime.state, Runtime.Config.palletJack)
            local signature = table.concat({
                tostring(jack.operating == true),
                tostring(jack.operatorPlayerId or "none"),
                tostring(Runtime.state.cutter and Runtime.state.cutter.moving == true),
                tostring(Runtime.state.wrapper and Runtime.state.wrapper.moving == true),
                tostring(Runtime.state.windmill and Runtime.state.windmill.moving == true),
            }, ":")
            if signature ~= Runtime.acceptanceHostRelocationSignature then
                Runtime.acceptanceHostRelocationSignature = signature
                print(string.format(
                    "[ACCEPTANCE HOST] RELOCATION jack=%s owner=%s cutter=%s wrapper=%s windmill=%s",
                    tostring(jack.operating == true), tostring(jack.operatorPlayerId or "none"),
                    tostring(Runtime.state.cutter and Runtime.state.cutter.moving == true),
                    tostring(Runtime.state.wrapper and Runtime.state.wrapper.moving == true),
                    tostring(Runtime.state.windmill and Runtime.state.windmill.moving == true)))
                io.flush()
            end
        end
        if Runtime.multiplayer:isClient() then
            local jack = Runtime.PalletJack.ensure(Runtime.state, Runtime.Config.palletJack)
            -- Predicting drivers already advanced their turn during movement.
            -- Observers (including clients in menus) still need one visual step.
            local presentationDt = predictedJackOwner ~= nil
                and predictedJackOwner == jack.operatorPlayerId and 0 or dt
            Runtime.World.updatePalletJackPresentation(Runtime.state, presentationDt,
                Runtime.multiplayer:remotePlayers(), Runtime.World.player)
        end
    end
end

return Component
