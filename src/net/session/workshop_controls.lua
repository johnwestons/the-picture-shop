-- Workshop command and release controls.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:requestWorkshopCommand(action, arguments)
        local active = self.activeWorkshop
        if not self:isClient() or self.terminal or not self.ready or not self.sessionId
            or not active
        then
            return false, "No host-authorized workshop console is open."
        end
        arguments = type(arguments) == "table" and arguments or {}
        local urgentSafety = Runtime.urgentWorkshopSafety(active.resourceId, action, arguments)
        if self.pendingWorkshopSafety then
            return false, "Waiting for the host to confirm the urgent workshop safety action."
        end
        if self.pendingWorkshop and not urgentSafety then
            return false, "Waiting for the host to answer the previous workshop action."
        end
        self.workshopRequestId = self.workshopRequestId + 1
        local request = {
            sessionId = self.sessionId,
            commandId = self.workshopRequestId,
            leaseId = active.leaseId,
            resourceId = active.resourceId,
            action = action,
            expectedRevision = active.revision,
        }
        if action == "submit_quote" then request.amount = arguments.amount
        elseif action == "purchase_stock" or action == "purchase_machine"
            or action == "move_item" or action == "service_view"
            or action == "service_tool" or action == "service_point"
            or action == "remove_blade_bolt" or action == "service_target"
        then
            request.itemIndex = arguments.itemIndex
        elseif action == "request_pickup" then request.jobId = arguments.jobId
        elseif action == "office_action" then request.officeIntent = arguments.officeIntent
        elseif action == "warehouse_action" then request.warehouseIntent = arguments.warehouseIntent
        elseif action == "phone_answer" or action == "phone_respond" or action == "phone_dismiss" then
            request.callId = arguments.callId
        elseif action == "select_pallet" or action == "start_cycle"
            or action == "lift_pallet" or action == "lower_pallet"
            or action == "load_pallet"
        then
            request.palletId = arguments.palletId
            if action == "lower_pallet" then request.placementCell = arguments.placementCell end
        elseif action == "select_program" then
            request.programIndex = arguments.programIndex
        elseif action == "set_gauge" then
            request.gaugeCentiInch = arguments.gaugeCentiInch
        elseif action == "set_clamp" then
            request.clamp = arguments.clamp
        elseif action == "set_barrier" then
            request.barrierClear = arguments.barrierClear
        elseif action == "set_weekly_technician" then
            request.enabled = arguments.enabled
        elseif action == "move_machine" then
            request.machineIndex = arguments.machineIndex
            request.machineId = arguments.machineId
        elseif action == "place_machine" then
            request.placementCell = arguments.placementCell
        elseif action == "order_plate" or action == "begin_plate" or action == "process_plate" then
            request.plateId = arguments.plateId
        elseif action == "begin_setup" then
            request.setupTask = arguments.setupTask
        elseif action == "setup_action" then
            request.setupAction = arguments.setupAction
        end
        local ok, errorMessage = self:_sendToServer("workshop_command", request)
        if not ok then return false, errorMessage end
        local pending = {
            operation = "command",
            commandId = request.commandId,
            resourceId = request.resourceId,
            action = request.action,
            sentAt = self.clock(),
        }
        if urgentSafety then
            self.pendingWorkshopSafety = pending
        else
            self.pendingWorkshop = pending
        end
        return true
    end

    function Runtime.Session:releaseWorkshop(reason)
        local active = self.activeWorkshop
        if not self:isClient() or self.terminal or not self.ready or not self.sessionId
            or not active
        then
            return false
        end
        self.workshopRequestId = self.workshopRequestId + 1
        local request = {
            sessionId = self.sessionId,
            requestId = self.workshopRequestId,
            leaseId = active.leaseId,
            resourceId = active.resourceId,
            reason = reason == "cancelled" and "cancelled" or "closed",
        }
        local ok, errorMessage = self:_sendToServer("workshop_release", request)
        if not ok then return false, errorMessage end
        self.activeWorkshop, self.pendingWorkshop, self.pendingWorkshopSafety = nil, nil, nil
        return true
    end

    function Runtime.Session:workshopInfo()
        if not self.activeWorkshop then return nil end
        return {
            resourceId = self.activeWorkshop.resourceId,
            leaseId = self.activeWorkshop.leaseId,
            revision = self.activeWorkshop.revision,
        }
    end

    function Runtime.Session:markShopDirty(urgent)
        if not self:isHost() or self.terminal then return false end
        self.shopDirty = true
        if urgent == true then self.shopStateAccumulator = Runtime.SHOP_STATE_INTERVAL end
        return true
    end

    function Runtime.Session:remotePlayers()
        local result = {}
        for id, player in pairs(self.players) do
            if id ~= self.localId then result[#result + 1] = player end
        end
        table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
        return result
    end

    function Runtime.Session:hudInfo()
        local pendingJoins = {}
        if self:isHost() and self.networkKind == "direct" and not self.terminal then
            local now = self.clock()
            for requestId, pending in pairs(self.approvalRequests) do
                if type(pending) == "table" and pending.stage == "approval" then
                    local remaining = Runtime.finite(now) and Runtime.finite(pending.requestedAt)
                        and math.max(0, Runtime.DIRECT_APPROVAL_TIMEOUT - (now - pending.requestedAt)) or 0
                    pendingJoins[#pendingJoins + 1] = {
                        requestId = requestId,
                        name = pending.name,
                        character = pending.character,
                        expiresIn = math.floor(remaining + 0.5),
                    }
                end
            end
            table.sort(pendingJoins, function(left, right)
                return left.requestId < right.requestId
            end)
        end
        local connectedGuests = {}
        if self:isHost() and self.networkKind == "direct" then
            for id, player in pairs(self.players) do
                if id ~= self.localId then
                    connectedGuests[#connectedGuests + 1] = {
                        playerId = id,
                        name = tostring(player.name or "Worker"),
                        character = tostring(player.character or "rabbit-worker"),
                    }
                end
            end
            table.sort(connectedGuests, function(left, right)
                return left.playerId < right.playerId
            end)
        end
        local players = {}
        for id, player in pairs(self.players) do
            players[#players + 1] = {
                playerId = id,
                name = tostring(player.name or "Worker"),
                isHost = id == 1,
                isLocal = id == self.localId,
            }
        end
        table.sort(players, function(left, right)
            return left.playerId < right.playerId
        end)
        local pendingActivity
        if self.pendingWorkshopSafety then
            pendingActivity = {
                kind = "urgent_safety",
                resourceId = self.pendingWorkshopSafety.resourceId,
                action = self.pendingWorkshopSafety.action,
            }
        elseif self.pendingWorkshop then
            pendingActivity = {
                kind = self.pendingWorkshop.operation == "acquire"
                    and "workshop_acquire" or "workshop_action",
                resourceId = self.pendingWorkshop.resourceId,
                action = self.pendingWorkshop.action,
            }
        elseif self.pendingInteraction then
            pendingActivity = {
                kind = "interaction",
                targetKind = self.pendingInteraction.targetKind,
            }
        end
        local workshopResources = {}
        for _, resource in ipairs(self.workshopResources or {}) do
            workshopResources[#workshopResources + 1] = {
                resourceId = resource.resourceId,
                occupied = resource.occupied == true,
                ownerPlayerId = resource.occupied and resource.ownerPlayerId or nil,
            }
        end
        return {
            mode = self.mode,
            networkKind = self.networkKind,
            status = self.status,
            playerCount = Runtime.countEntries(self.players),
            address = self.localAddress,
            port = self.port,
            rtt = self.rtt,
            canManage = self:isHost() and self.networkKind == "direct" and not self.terminal,
            pendingJoinCount = #pendingJoins,
            pendingJoins = pendingJoins,
            connectedGuests = connectedGuests,
            localPlayerId = self.localId,
            players = players,
            activeResourceId = self.activeWorkshop and self.activeWorkshop.resourceId or nil,
            pendingActivity = pendingActivity,
            workshopResources = workshopResources,
        }
    end
end

return Component
