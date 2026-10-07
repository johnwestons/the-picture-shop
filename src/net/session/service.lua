-- Transport servicing and host simulation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_service(context)
        if not self.transport or self.terminal then return false end
        local events, serviceError = self.transport:service(Runtime.Protocol.MAX_EVENTS_PER_UPDATE)
        if serviceError then
            self.protocolRejectionAt = {}
            self:_markDisconnected("Network transport failed: " .. tostring(serviceError))
            self:_closeTransport(2, true)
            return false
        end
        for _, event in ipairs(events or {}) do
            if self.mode == "host" then
                if event.type == "connect" then
                    local now = self.clock()
                    local generation = self:_nextRuntimeHandle("nextConnectionGeneration")
                    if not event.peer or not Runtime.finite(now) or not generation then
                        if event.peer then self.transport:disconnect(event.peer, 7, true) end
                    elseif self.pendingPeers[event.peer] or self.peerToId[event.peer] then
                        -- One authenticated link generation may create only one
                        -- Session admission. A fresh single-use invitation arrives
                        -- as a distinct link after the prior generation is gone.
                        self.transport:disconnect(event.peer, 7, true)
                    else
                        self.protocolRejectionAt[event.peer] = nil
                        self.pendingPeers[event.peer] = {
                            peer = event.peer,
                            connectedAt = now,
                            generation = generation,
                            stage = "hello",
                        }
                    end
                elseif event.type == "disconnect" then
                    self:_removePeer(event.peer, "Connection lost")
                elseif event.type == "receive" then
                    local packet = event.data or event.payload
                    local channel = tonumber(event.channel)
                    local envelope, decodeError
                    if type(packet) ~= "string" then
                        decodeError = "protocol: packet must be a string"
                    elseif channel == nil or channel < 0 or channel >= Runtime.Protocol.CHANNEL_COUNT
                        or channel ~= math.floor(channel)
                    then
                        decodeError = "protocol: packet arrived on an invalid channel"
                    elseif #packet > Runtime.Protocol.MAX_PACKET_BYTES then
                        -- Guests have no legal durable/save-sized message. Reject
                        -- before the expensive large-codec decode path.
                        decodeError = "protocol: guest packet exceeds maximum size"
                    else
                        envelope, decodeError = Runtime.Protocol.decode(packet)
                        if envelope then
                            local expectedChannel = Runtime.Protocol.route(envelope)
                            if channel ~= expectedChannel then
                                local wrongKind = envelope.type
                                envelope = nil
                                decodeError = "protocol: " .. tostring(wrongKind)
                                    .. " arrived on the wrong channel"
                            end
                        end
                    end
                    if not envelope then
                        if self.networkKind == "direct" and self.pendingPeers[event.peer] then
                            self:_rejectDirectPending(event.peer, "invalid_join",
                                "The Direct join request was not valid.",
                                "One invalid Direct join was rejected.")
                        else
                            self:_sendProtocolRejection(event.peer, "bad_packet", decodeError)
                        end
                    else
                        self:_handleHostEnvelope(event.peer, envelope, context)
                    end
                end
            else
                if event.type == "connect" then
                    local ok, helloError = self:_sendToServer("hello", {
                        clientNonce = self.clientNonce,
                        name = self.localName,
                        character = self.localCharacter,
                        furColorway = self.localFurColorway or 1,
                        overallsColorway = self.localOverallsColorway or 1,
                    })
                    if not ok then self:_queue("error", { message = helloError }) end
                    self.connectedAt = self.clock()
                    self.status = "Connected; waiting for host approval"
                    if self.networkKind == "direct" and ok then
                        self:_queue("approval_waiting", {
                            message = "Encrypted request sent. Waiting for the host to approve this player.",
                        })
                    end
                elseif event.type == "disconnect" then
                    self:_markDisconnected(self.disconnectReason or "The host connection ended.")
                elseif event.type == "receive" then
                    local packet = event.data or event.payload
                    local channel = tonumber(event.channel)
                    local envelope, decodeError
                    if type(packet) ~= "string" then
                        decodeError = "protocol: packet must be a string"
                    elseif channel == nil or channel < 0 or channel >= Runtime.Protocol.CHANNEL_COUNT
                        or channel ~= math.floor(channel)
                    then
                        decodeError = "protocol: packet arrived on an invalid channel"
                    else
                        local limit = channel == Runtime.Protocol.CHANNEL_DURABLE
                            and Runtime.Protocol.MAX_SHOP_SNAPSHOT_BYTES or Runtime.Protocol.MAX_PACKET_BYTES
                        if #packet > limit then
                            decodeError = "protocol: host packet exceeds channel size limit"
                        else
                            envelope, decodeError = Runtime.Protocol.decode(packet)
                            if envelope then
                                local expectedChannel = Runtime.Protocol.route(envelope)
                                if channel ~= expectedChannel then
                                    envelope = nil
                                    decodeError = "protocol: host packet arrived on the wrong channel"
                                end
                            end
                        end
                    end
                    if not envelope then
                        self:_queue("error", { message = "Host sent an invalid packet: " .. tostring(decodeError) })
                    else
                        self:_handleClientEnvelope(envelope)
                    end
                end
            end
            if self.terminal then break end
        end
        if self.terminal then self:_closeTransport(1, true) end
        return not self.terminal
    end

    function Runtime.Session:_updateHost(dt, context)
        self:_syncLocalPlayer(context and context.localPlayer)
        if context and type(context.touchWorkshop) == "function" and self.players[self.localId] then
            context.touchWorkshop(self.players[self.localId])
        end
        local now = self.clock()
        local expiredPeers = {}
        local approvedPeers = {}
        for peer, pending in pairs(self.pendingPeers) do
            local connectedAt = type(pending) == "table" and pending.connectedAt or pending
            local stage = type(pending) == "table" and pending.stage or "hello"
            local requestedAt = type(pending) == "table" and pending.requestedAt or nil
            if not Runtime.finite(now) or not Runtime.finite(connectedAt) or now < connectedAt
                or (stage == "approval" and (not Runtime.finite(requestedAt) or now < requestedAt))
            then
                expiredPeers[#expiredPeers + 1] = { peer = peer, stage = stage, invalidClock = true }
            elseif stage == "approval" and now - requestedAt > Runtime.DIRECT_APPROVAL_TIMEOUT then
                expiredPeers[#expiredPeers + 1] = { peer = peer, stage = stage }
            elseif stage == "hello" and now - connectedAt > Runtime.CONNECT_TIMEOUT then
                expiredPeers[#expiredPeers + 1] = { peer = peer, stage = stage }
            elseif stage == "approval" and pending.decision == "approved" then
                approvedPeers[#approvedPeers + 1] = { peer = peer, pending = pending }
            end
        end
        for _, expired in ipairs(expiredPeers) do
            local peer = expired.peer
            if self.networkKind == "direct" then
                local approval = expired.stage == "approval"
                self:_rejectDirectPending(peer,
                    approval and "approval_timeout" or "hello_timeout",
                    approval and "The host did not approve this Direct request in time."
                        or "The Direct join request did not finish in time.",
                    approval and "One Direct approval timed out; the host remains open."
                        or "One Direct join timed out; the host remains open.",
                    approval and "join_expired" or "join_cancelled")
            else
                self:_discardPendingPeer(peer)
                self.protocolRejectionAt[peer] = nil
                self:_sendError(peer, "hello_timeout", "The client did not complete the LAN hello in time.")
                self.transport:disconnect(peer, 3, false)
            end
        end
        for _, approved in ipairs(approvedPeers) do
            local pending = approved.pending
            if self.pendingPeers[approved.peer] == pending
                and self.approvalRequests[pending.requestId] == pending
                and pending.decision == "approved"
            then
                self:_hostWelcome(approved.peer, pending.hello, context)
            end
        end
        for id, player in pairs(self.players) do
            if id ~= self.localId then
                local inputX, inputY = player.inputX or 0, player.inputY or 0
                if now - (player.lastInputAt or 0) > Runtime.INPUT_HOLD_TIMEOUT then inputX, inputY = 0, 0 end
                if context and context.moveRemote then
                    context.moveRemote(player, dt, inputX, inputY)
                end
            end
        end
        -- Requests are resolved only after this frame's authoritative remote
        -- movement, reducing false range failures near an interaction boundary.
        self:_processHostInteractions(context)
        self:_processHostHighFives()
        self:_processHostWorkshop(context)
        if context and type(context.updateWorkshop) == "function" then
            context.updateWorkshop()
        end
        self.snapshotAccumulator = self.snapshotAccumulator + dt
        if self.snapshotAccumulator >= Runtime.SNAPSHOT_INTERVAL and next(self.idToPeer) then
            self.snapshotAccumulator = self.snapshotAccumulator % Runtime.SNAPSHOT_INTERVAL
            self.serverTick = self.serverTick + 1
            -- Motion is intentionally sent as one player per packet. Every shard
            -- shares the tick, and clients merge them by player id. This keeps four
            -- real, full-precision poses under the 1,200-byte unreliable limit.
            for _, record in ipairs(self:_records()) do
                local ok, errorMessage = self:_broadcastJoined("snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    players = Runtime.Codec.array({ record }),
                })
                if not ok then
                    self:_queue("error", { message = errorMessage })
                    break
                end
            end
            local visitors = context and context.getVisitorSnapshot
                and context.getVisitorSnapshot() or nil
            if type(visitors) == "table" and type(visitors.customer) == "table"
                and type(visitors.vendor) == "table"
            then
                local visitorsOk, visitorsError = self:_broadcastJoined("visitor_snapshot", {
                    sessionId = self.sessionId,
                    serverTick = self.serverTick,
                    customer = visitors.customer,
                    vendor = visitors.vendor,
                })
                if not visitorsOk then self:_queue("error", { message = visitorsError }) end
            end
            local environment = context and context.getEnvironmentSnapshot
                and context.getEnvironmentSnapshot() or nil
            if type(environment) == "table" and type(environment.bayDoor) == "table"
                and type(environment.truck) == "table"
            then
                local environmentOk, environmentError = self:_broadcastJoined(
                    "environment_snapshot", {
                        sessionId = self.sessionId,
                        serverTick = self.serverTick,
                        bayDoor = environment.bayDoor,
                        truck = environment.truck,
                        employees = environment.employees,
                    })
                if not environmentOk then self:_queue("error", { message = environmentError }) end
            end
            local palletJack = context and context.getPalletJackSnapshot
                and context.getPalletJackSnapshot() or nil
            local machinePoses = context and context.getMachinePoseSnapshot
                and context.getMachinePoseSnapshot() or nil
            if type(palletJack) == "table" and type(machinePoses) == "table" then
                local palletJackOk, palletJackError, palletJackRecipients = self:_broadcastJoined(
                    "pallet_jack_snapshot", {
                        sessionId = self.sessionId,
                        serverTick = self.serverTick,
                        jack = palletJack,
                        machines = machinePoses,
                    })
                if os.getenv("PICTURE_SHOP_ACCEPTANCE_HOST_SLOT") then
                    local relocationSignature = table.concat({
                        tostring(palletJack.operating == true),
                        tostring(palletJack.operatorPlayerId or "none"),
                        tostring(machinePoses.cutter and machinePoses.cutter.moving == true),
                        tostring(machinePoses.wrapper and machinePoses.wrapper.moving == true),
                        tostring(machinePoses.windmill and machinePoses.windmill.moving == true),
                        tostring(palletJackOk == true),
                        tostring(palletJackRecipients or 0),
                        tostring(palletJackError or "none"),
                    }, ":")
                    if relocationSignature ~= self._acceptanceRelocationSendSignature then
                        self._acceptanceRelocationSendSignature = relocationSignature
                        print(string.format(
                            "[ACCEPTANCE HOST] SNAPSHOT jack=%s owner=%s cutter=%s wrapper=%s windmill=%s sent=%s recipients=%s error=%s",
                            tostring(palletJack.operating == true),
                            tostring(palletJack.operatorPlayerId or "none"),
                            tostring(machinePoses.cutter and machinePoses.cutter.moving == true),
                            tostring(machinePoses.wrapper and machinePoses.wrapper.moving == true),
                            tostring(machinePoses.windmill and machinePoses.windmill.moving == true),
                            tostring(palletJackOk == true), tostring(palletJackRecipients or 0),
                            tostring(palletJackError or "none")))
                        io.flush()
                    end
                end
                if not palletJackOk then self:_queue("error", { message = palletJackError }) end
            end
            local forklift = context and context.getForkliftSnapshot
                and context.getForkliftSnapshot() or nil
            if type(forklift) == "table" then
                local liftOk, liftError = self:_broadcastJoined("forklift_snapshot", {
                    sessionId = self.sessionId, serverTick = self.serverTick, forklift = forklift,
                })
                if not liftOk then self:_queue("error", { message = liftError }) end
            end
            local cutter = context and context.getCutterSnapshot
                and context.getCutterSnapshot() or nil
            local cutterSnapshots = cutter and (cutter.view and { cutter } or cutter) or {}
            for _, item in ipairs(cutterSnapshots) do
                if type(item.view) == "table" then
                    local resourceId = item.resourceId or "cutter"
                    local cutterOk, cutterError = self:_broadcastJoined("cutter_snapshot", {
                        sessionId = self.sessionId,
                        serverTick = self.serverTick,
                        resourceId = resourceId,
                        resourceRevision = item.resourceRevision,
                        view = Runtime.wireWorkshopView(resourceId, item.view),
                    })
                    if not cutterOk then self:_queue("error", { message = cutterError }) end
                end
            end
            local windmill = context and context.getWindmillSnapshot
                and context.getWindmillSnapshot() or nil
            local windmillSnapshots = windmill and (windmill.view and { windmill } or windmill) or {}
            for _, item in ipairs(windmillSnapshots) do
                if type(item.view) == "table" then
                    local resourceId = item.resourceId or "windmill"
                    local windmillOk, windmillError = self:_broadcastJoined("windmill_snapshot", {
                        sessionId = self.sessionId,
                        serverTick = self.serverTick,
                        resourceId = resourceId,
                        resourceRevision = item.resourceRevision,
                        view = Runtime.wireWorkshopView(resourceId, item.view),
                    })
                    if not windmillOk then self:_queue("error", { message = windmillError }) end
                end
            end
            local wrappers = context and context.getWrapperSnapshots
                and context.getWrapperSnapshots() or {}
            for _, item in ipairs(wrappers) do
                if type(item.view) == "table" then
                    local wrapperOk, wrapperError = self:_broadcastJoined("wrapper_snapshot", {
                        sessionId = self.sessionId,
                        serverTick = self.serverTick,
                        resourceId = item.resourceId,
                        resourceRevision = item.resourceRevision,
                        view = Runtime.wireWorkshopView(item.resourceId, item.view),
                    })
                    if not wrapperOk then self:_queue("error", { message = wrapperError }) end
                end
            end
            local workshop = context and context.getWorkshopSnapshot
                and context.getWorkshopSnapshot() or nil
            if type(workshop) == "table" and type(workshop.resources) == "table"
                and type(workshop.wrapper) == "table"
            then
                local workshopOk, workshopError = self:_broadcastJoined(
                    "workshop_snapshot", {
                        sessionId = self.sessionId,
                        revision = self.serverTick,
                        resources = workshop.resources,
                        wrapper = Runtime.wireWorkshopView("skid_wrapper", workshop.wrapper),
                    })
                if not workshopOk then self:_queue("error", { message = workshopError }) end
            end
        end


        self.shopStateAccumulator = math.min(
            Runtime.SHOP_STATE_INTERVAL, self.shopStateAccumulator + dt)
        self.shopFallbackAccumulator = self.shopFallbackAccumulator + dt
        if self.shopFallbackAccumulator >= Runtime.SHOP_STATE_FALLBACK_INTERVAL then self.shopDirty = true end
        if self.shopDirty and self.shopStateAccumulator >= Runtime.SHOP_STATE_INTERVAL
            and next(self.idToPeer) then
            local shop = context and context.getShopSnapshot and context.getShopSnapshot() or nil
            if type(shop) ~= "table" or type(shop.state) ~= "table" then
                self:_queue("error", { message = "The host could not prepare a durable shop update." })
                self.shopStateAccumulator = 0
            else
                local revision = self.shopRevision + 1
                local stateOk, stateError, recipientCount = self:_broadcastJoined("shop_state", {
                    sessionId = self.sessionId,
                    revision = revision,
                    state = shop.state,
                })
                self.shopStateAccumulator = 0
                if stateOk then
                    if recipientCount > 0 then self.shopRevision = revision end
                    self.shopDirty = false
                    self.shopFallbackAccumulator = 0
                else
                    self:_queue("error", { message = stateError })
                end
            end
        end
    end
end

return Component
