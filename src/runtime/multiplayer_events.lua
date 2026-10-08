-- Applying multiplayer events to shop presentation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.handleMultiplayerEvents()
        for _, event in ipairs(Runtime.multiplayer:drainEvents()) do
            if event.type == "ready" then
                Runtime.warehouseControls:resolve(Runtime.warehousePendingIntent,false,"The warehouse connection was restarted.")
                Runtime.warehousePendingIntent=nil
                Runtime.warehouseControls:reset("The warehouse connection was restarted.")
                Runtime.Machine.resetNetworkReplica()
                if not Runtime.State.applySharedSnapshot(Runtime.state, event.state) then
                    Runtime.showConnectionError(
                        "The host sent a shop snapshot this build could not apply.",
                        "Invalid shared shop snapshot")
                else
                    if Runtime.multiplayer:isClient() and Runtime.multiplayer.networkKind == "lan" then
                        Runtime.lanReconnectArmed = true
                        Runtime.lanReconnect:succeeded()
                        Runtime.lanDiscovery:stop()
                    end
                    Runtime.World.load(event.spawn)
                    Runtime.App.syncPlayerColorways()
                    Runtime.state.screen = "world"
                    Runtime.state.message = "Joined the host shop. Movement, doors, reception, office, cutter, wrapper, and Windmill controls are live."
                    Runtime.DirectScreen.leave()
                end
                Runtime.syncMobileKeyboard()
            elseif event.type == "shop_state" then
                if not Runtime.State.applySharedUpdate(Runtime.state, event.state) then
                    Runtime.showConnectionError(
                        "The host sent a shop update this build could not apply.",
                        "Invalid durable shop update")
                end
            elseif event.type == "radio_state" then
                require("src.jukebox").applyNetworkState(event)
            elseif event.type == "forklift_state" then
                local applied,reason=Runtime.Forklift.applySnapshot(Runtime.state,event.forklift,Runtime.Config.forklift)
                if not applied and reason~="awaiting_durable" and reason~="operator_conflict" then
                    Runtime.state.message="Forklift update waiting for a fresh host state: "..tostring(reason)
                end
            elseif event.type == "pallet_jack_state" then
                local applied, applyError = Runtime.World.applyNetworkPalletJackSnapshot(
                    Runtime.state, event.jack, event.machines)
                if not applied and applyError ~= "awaiting_durable" then
                    Runtime.showConnectionError(
                        "The host sent a pallet-jack update this build could not apply.",
                        "Invalid pallet-jack update")
                end
            elseif event.type == "visitor_state" then
                if not Runtime.World.applyVisitorSnapshot(event.customer, event.vendor) then
                    Runtime.showConnectionError(
                        "The host sent a visitor update this build could not apply.",
                        "Invalid visitor update")
                end
            elseif event.type == "employee_state" then
                Runtime.World.applyEmployeeSnapshot(event.employees,Runtime.state)
            elseif event.type == "environment_state" then
                if not Runtime.World.applyEnvironmentSnapshot(event.bayDoor, event.truck, event.employees, Runtime.state) then
                    Runtime.showConnectionError(
                        "The host sent an environment update this build could not apply.",
                        "Invalid environment update")
                end
            elseif event.type == "interaction_result" then
                Runtime.state.message = tostring(event.message or (event.accepted
                    and "The host accepted the interaction."
                    or "The host rejected the interaction."))
            elseif event.type == "workshop_grant" then
                Runtime.state.message = tostring(event.message or (event.granted
                    and "Workshop control granted." or "Workshop control was not granted."))
                if event.granted then
                    local machineBase, machineId = Runtime.MachineResource.parse(event.resourceId)
                    if machineBase == "skid_wrapper" and event.view then
                        Runtime.Wrapper.select(machineId, Runtime.state)
                        Runtime.Wrapper.applySnapshot(event.view, Runtime.state)
                    elseif machineBase == "cutter" and event.view then
                        Runtime.Machine.select(machineId, Runtime.state)
                        Runtime.Machine.applyNetworkView(event.view)
                    end
                    if event.resourceId == "warehouse" then
                        if Runtime.warehousePendingIntent then
                            local sent,message=Runtime.multiplayer:requestWorkshopCommand("warehouse_action",
                                {warehouseIntent=Runtime.warehousePendingIntent})
                            if not sent then
                                Runtime.warehouseControls:resolve(Runtime.warehousePendingIntent,false,message)
                                Runtime.warehousePendingIntent=nil
                                Runtime.state.message=message
                                Runtime.multiplayer:releaseWorkshop("cancelled")
                            end
                        end
                    elseif event.resourceId == "pallet_jack" then
                        Runtime.state.screen = "world"
                    else
                        event.useHostLayout = true
                        Runtime.WorkshopRemoteScreen.enter(event, Runtime.state)
                    end
                end
                if not event.granted and event.resourceId=="warehouse" then
                    Runtime.warehouseControls:resolve(Runtime.warehousePendingIntent,false,event.message)
                    Runtime.warehousePendingIntent=nil
                end
                Runtime.syncMobileKeyboard()
            elseif event.type == "workshop_result" then
                if event.action=="warehouse_action" then
                    Runtime.warehouseControls:resolve(Runtime.warehousePendingIntent,event.accepted,event.message)
                    if event.accepted and Runtime.warehousePendingIntent and Runtime.warehousePendingIntent.kind=="release" then
                        Runtime.multiplayer:releaseWorkshop("closed")
                    elseif not event.accepted and event.resourceId=="warehouse"
                        and Runtime.warehousePendingIntent and Runtime.warehousePendingIntent.kind=="operate" then
                        Runtime.multiplayer:releaseWorkshop("cancelled")
                    end
                    Runtime.warehousePendingIntent=nil
                end
                local machineBase, machineId = Runtime.MachineResource.parse(event.resourceId)
                if machineBase == "skid_wrapper" and event.view then
                    Runtime.Wrapper.select(machineId, Runtime.state)
                    Runtime.Wrapper.applySnapshot(event.view, Runtime.state)
                elseif machineBase == "cutter" and event.view then
                    Runtime.Machine.select(machineId, Runtime.state)
                    Runtime.Machine.applyNetworkView(event.view)
                end
                if event.resourceId ~= "pallet_jack" and event.resourceId ~= "warehouse" then
                    Runtime.WorkshopRemoteScreen.applyResult(event)
                end
                Runtime.state.message = tostring(event.message or (event.accepted
                    and "Workshop action completed." or "Workshop action was rejected."))
                if event.accepted and event.resourceId == "reception_customer" then
                    Runtime.multiplayer:releaseWorkshop("closed")
                    Runtime.WorkshopRemoteScreen.clear()
                    Runtime.state.screen = "world"
                elseif event.accepted and event.resourceId == "vendor"
                    and event.action == "dismiss"
                then
                    Runtime.multiplayer:releaseWorkshop("closed")
                    Runtime.WorkshopRemoteScreen.clear()
                    Runtime.state.screen = "world"
                elseif event.accepted and event.resourceId == "truck"
                    and event.action == "close_truck"
                then
                    Runtime.multiplayer:releaseWorkshop("closed")
                    Runtime.WorkshopRemoteScreen.clear()
                    Runtime.state.screen = "world"
                elseif event.accepted and event.resourceId == "pallet_jack"
                    and event.action == "park_jack"
                then
                    Runtime.multiplayer:releaseWorkshop("closed")
                end
                Runtime.syncMobileKeyboard()
            elseif event.type == "workshop_snapshot" then
                local activeBase, activeMachineId = Runtime.MachineResource.parse(
                    Runtime.WorkshopRemoteScreen.leaseResourceId)
                Runtime.Wrapper.select(nil, Runtime.state)
                local wrapperApplied = Runtime.Wrapper.applySnapshot(event.wrapper, Runtime.state)
                if activeBase == "skid_wrapper" then
                    Runtime.Wrapper.select(activeMachineId, Runtime.state)
                end
                if not wrapperApplied then
                    Runtime.showConnectionError(
                        "The host sent a workshop update this build could not apply.",
                        "Invalid workshop runtime")
                else
                    Runtime.WorkshopRemoteScreen.applySnapshot(event)
                end
            elseif event.type == "cutter_state" then
                if Runtime.WorkshopRemoteScreen.leaseResourceId == event.resourceId then
                    local _, machineId = Runtime.MachineResource.parse(event.resourceId)
                    Runtime.Machine.select(machineId, Runtime.state)
                    Runtime.Machine.applyNetworkView(event.view)
                end
                if Runtime.WorkshopRemoteScreen.applyCutterSnapshot then
                    Runtime.WorkshopRemoteScreen.applyCutterSnapshot(event)
                end
            elseif event.type == "windmill_state" then
                if Runtime.WorkshopRemoteScreen.applyWindmillSnapshot then
                    Runtime.WorkshopRemoteScreen.applyWindmillSnapshot(event)
                end
            elseif event.type == "wrapper_state" then
                if Runtime.WorkshopRemoteScreen.leaseResourceId == event.resourceId then
                    local _, machineId = Runtime.MachineResource.parse(event.resourceId)
                    Runtime.Wrapper.select(machineId, Runtime.state)
                    Runtime.Wrapper.applySnapshot(event.view, Runtime.state)
                    Runtime.WorkshopRemoteScreen.applyWrapperSnapshot(event)
                end
            elseif event.type == "workshop_lost" then
                Runtime.warehouseControls:resolve(Runtime.warehousePendingIntent,false,event.message or "Warehouse control disconnected.")
                Runtime.warehousePendingIntent=nil
                Runtime.warehouseControls:reset(event.message or "Warehouse control disconnected.")
                if Runtime.state.screen == "workshop_remote" then
                    Runtime.WorkshopRemoteScreen.clear()
                    Runtime.state.screen = "world"
                end
                if event.resourceId == "pallet_jack" then
                    local jack = Runtime.PalletJack.ensure(Runtime.state, Runtime.Config.palletJack)
                    local localId = tonumber(Runtime.World.player.id)
                    if jack.operatorPlayerId == localId then
                        Runtime.PalletJack.forceRelease(Runtime.state, Runtime.Config.palletJack, localId)
                    end
                elseif event.resourceId == "warehouse" then
                    local localId=tonumber(Runtime.World.player.id)
                    if Runtime.state.forklift and Runtime.state.forklift.operatorPlayerId==localId then
                        Runtime.World.forceReleaseForklift(Runtime.World.player,Runtime.state)
                    end
                end
                Runtime.state.message = tostring(event.message or "The host released that workshop control.")
                Runtime.syncMobileKeyboard()
            elseif event.type == "host_started" then
                if event.networkKind == "direct" then
                    Runtime.state.message = "Direct host active. Each invited worker needs separate approval before any shop data is shared."
                else
                    local address = event.address or "the host device's Wi-Fi IPv4"
                    Runtime.state.message = "LAN host: nearby workers can find this shop, or join manually at "
                        .. tostring(address) .. ":" .. tostring(event.port or 22122) .. "."
                end
            elseif event.type == "approval_waiting" then
                Runtime.DirectScreen.setMessage(event.message
                    or "Encrypted request sent. Waiting for the host to approve this player.",
                    "connecting")
            elseif event.type == "join_requested" then
                Runtime.MultiplayerHud.open(Runtime.multiplayerHudInfo())
                Runtime.state.message = tostring(event.name or "A player")
                    .. " requested access. Choose APPROVE or DENY in the Players panel."
            elseif event.type == "join_cancelled" then
                Runtime.state.message = "The pending Direct player disconnected. That invitation is now closed."
            elseif event.type == "join_rejected" then
                Runtime.state.message = "Join declined. The old Direct codes can no longer be used."
            elseif event.type == "join_expired" then
                Runtime.state.message = "The Direct join request expired. Create fresh codes to try again."
            elseif event.type == "player_joined" then
                Runtime.state.message = tostring(event.name or "A worker") .. " joined the shop."
            elseif event.type == "player_left" then
                if Runtime.workshopAuthority then
                    Runtime.workshopAuthority:cleanupPlayer({ id = event.playerId }, "disconnected",
                        { state = Runtime.state })
                end
                local label = Runtime.multiplayer.networkKind == "direct" and "Direct" or "LAN"
                Runtime.state.message = tostring(event.name or "A worker") .. " left the " .. label .. " shop."
            elseif event.type == "player_kicked" then
                Runtime.state.message = tostring(event.name or "A worker") .. " was removed by the host."
            elseif event.type == "direct_closed" then
                local message = tostring(event.message or
                    "This Direct invitation is closed. Create fresh codes before reconnecting.")
                require("src.jukebox").stopNetworkPlayback()
                Runtime.multiplayer:stop("Direct invitation closed")
                Runtime.clearWorkshopAuthority("direct_invitation_closed")
                Runtime.MultiplayerHud.reset()
                Runtime.state.message = message
            elseif event.type == "disconnected" then
                -- A host transport failure is terminal too. Release every workshop
                -- lease before leaving gameplay so its safety callback stops the
                -- Windmill and persists that stopped state.
                Runtime.clearWorkshopAuthority("transport_failed")
                Runtime.WorkshopRemoteScreen.clear()
                require("src.jukebox").stopNetworkPlayback()
                local lanClient = Runtime.multiplayer:isClient() and Runtime.multiplayer.networkKind == "lan"
                if not lanClient or not Runtime.handleLanReconnectFailure(
                    event.message or "The host connection ended.")
                then
                    Runtime.showConnectionError(event.message or "The host connection ended.", "Host disconnected")
                end
            elseif event.type == "error" then
                local lanClient = Runtime.multiplayer:isClient() and Runtime.multiplayer.networkKind == "lan"
                if lanClient and Runtime.FATAL_LAN_RECONNECT_ERRORS[event.code] then
                    Runtime.lanReconnectArmed = false
                    Runtime.lanReconnect:cancel(false)
                end
                local addingDirectWorker = Runtime.state.screen == "direct"
                    and Runtime.multiplayer:isHost() and Runtime.multiplayer.networkKind == "direct"
                    and Runtime.DirectScreen.inviteOnly == true
                if addingDirectWorker then
                    -- A joined worker can fail while the host is exchanging a
                    -- different worker's invitation.  Keep both the authoritative
                    -- shop and the fresh invitation alive; the Session/composite
                    -- transport isolates and retires only the failed link.
                    Runtime.DirectScreen.setMessage(
                        "One existing worker link ended; this fresh invitation is still active.")
                elseif Runtime.state.screen == "lan" and lanClient and Runtime.lanReconnect:isActive() then
                    Runtime.handleLanReconnectFailure(event.message or "The host did not answer.")
                elseif Runtime.state.screen == "lan" or Runtime.state.screen == "direct" then
                    Runtime.showConnectionError(event.message or "The multiplayer connection failed.",
                        "Connection error")
                else
                    local label = Runtime.multiplayer.networkKind == "direct" and "Direct" or "LAN"
                    Runtime.state.message = label .. ": " .. tostring(event.message or "network error")
                end
            end
        end
    end
end

return Component
