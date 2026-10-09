-- Client rosters, shop state, and incoming messages.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.Session:_installRoster(records, serverTick)
        local installed = {}
        local ticks = {}
        for _, record in ipairs(records or {}) do
            installed[record.id] = Runtime.newPlayer(record)
            if serverTick ~= nil then ticks[record.id] = serverTick end
        end
        self.players = installed
        self.lastPlayerTicks = ticks
    end

    function Runtime.Session:_acceptShopState(payload)
        if not self.ready or payload.sessionId ~= self.sessionId
            or payload.revision <= self.lastShopRevision
        then
            return false
        end
        self.lastShopRevision = payload.revision
        self:_queue("shop_state", {
            revision = payload.revision,
            state = payload.state,
        })
        return true
    end

    function Runtime.Session:_acceptInitialShopSnapshot(payload)
        if self.ready or not self.sessionId or payload.sessionId ~= self.sessionId then return false end
        local spawn = self.players[self.localId] and Runtime.playerRecord(self.players[self.localId])
        if not spawn then
            self:_queue("error", { message = "The host snapshot did not include this worker." })
            return false
        end
        self.lastShopRevision = payload.revision
        self.ready = true
        self.status = "Connected to the host"
        self:_queue("ready", {
            state = payload.state,
            hostPlayer = payload.player,
            spawn = spawn,
            playerId = self.localId,
            revision = payload.revision,
        })
        local pending = self.pendingShopState
        self.pendingShopState = nil
        if pending and pending.sessionId == self.sessionId then self:_acceptShopState(pending) end
        return true
    end

    function Runtime.Session:_bufferShopState(payload)
        local pending = self.pendingShopState
        if not pending or payload.revision > pending.revision then self.pendingShopState = payload end
    end

    function Runtime.Session:_applySnapshot(payload)
        if payload.sessionId ~= self.sessionId then return end
        if payload.games then self.roomGames=payload.games end
        if payload.balls then self.roomBalls=payload.balls end
        self.lastServerTick = math.max(self.lastServerTick, payload.serverTick)
        for _, record in ipairs(payload.players or {}) do
            local previousTick = self.lastPlayerTicks[record.id] or -1
            if payload.serverTick > previousTick then
                self.lastPlayerTicks[record.id] = payload.serverTick
                local player = self.players[record.id]
                if not player then
                    player = Runtime.newPlayer(record)
                    self.players[record.id] = player
                end
                player.name, player.character = record.name, record.character
                if (player.sceneId or "warehouse")~=(record.sceneId or "warehouse")
                    or (player.resting==true)~=(record.resting==true) then
                    Runtime.copyMotion(player,record,true)
                end
                player._targetX, player._targetY = record.x, record.y
                player._targetRecord = record
                if record.id == self.localId then
                    self.localTarget = record
                elseif (player.x - record.x) ^ 2 + (player.y - record.y) ^ 2
                    > Runtime.TELEPORT_DISTANCE * Runtime.TELEPORT_DISTANCE
                then
                    Runtime.copyMotion(player, record, true)
                end
            end
        end
    end

    function Runtime.Session:gameSnapshot()
        return self.roomGames or {}
    end

    function Runtime.Session:ballSnapshot()
        return self.roomBalls or {}
    end

    function Runtime.Session:fightSnapshot()
        return self.fightMatches or {}
    end

    function Runtime.Session:_handleClientEnvelope(envelope)
        local payload = envelope.payload
        if envelope.type == "welcome" then
            self.sessionId = payload.sessionId
            self.localId = payload.playerId
            self.lastServerTick = payload.serverTick - 1
            self.lastFightTick = -1
            self.fightMatches = {}
            self:_installRoster(payload.players, payload.serverTick)
            self.status = "Receiving the host shop..."
            local pending = self.pendingShopSnapshot
            self.pendingShopSnapshot = nil
            if pending and pending.sessionId == self.sessionId then
                self:_acceptInitialShopSnapshot(pending)
            end
        elseif envelope.type == "shop_snapshot" then
            if not self.sessionId then
                self.pendingShopSnapshot = payload
            elseif payload.sessionId == self.sessionId then
                self:_acceptInitialShopSnapshot(payload)
            end
        elseif envelope.type == "shop_state" then
            if not self.sessionId or not self.ready then
                self:_bufferShopState(payload)
            elseif payload.sessionId == self.sessionId then
                self:_acceptShopState(payload)
            end
        elseif envelope.type == "fight_snapshot" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > (self.lastFightTick or -1) then
                self.lastFightTick=payload.serverTick
                self.fightMatches=payload.matches
            end
        elseif envelope.type == "radio_state" then
            if self.sessionId and payload.sessionId == self.sessionId
                and payload.revision > self.lastRadioRevision
            then
                self.lastRadioRevision = payload.revision
                self:_queue("radio_state", {
                    revision = payload.revision,
                    trackIndex = payload.trackIndex,
                    active = payload.active,
                    paused = payload.paused,
                    muted = payload.muted,
                    positionMs = payload.positionMs,
                })
            end
        elseif envelope.type == "highfive_offer" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.receiverId == self.localId
            then
                local initiator = self.players[payload.initiatorId]
                self.highFiveOffers[payload.requestId] = {
                    requestId = payload.requestId,
                    initiatorId = payload.initiatorId,
                    receiverId = payload.receiverId,
                    initiatorName = tostring(initiator and initiator.name or "Worker"),
                    expiresAt = self.clock() + payload.expiresMs / 1000,
                }
            end
        elseif envelope.type == "highfive_request_result" then
            if self.ready and payload.sessionId == self.sessionId
                and self.highFiveOutgoing
                and self.highFiveOutgoing.clientRequestId == payload.clientRequestId
            then
                if payload.accepted then
                    self.highFiveOutgoing.requestId = payload.requestId
                    self.highFiveOutgoing.status = "offered"
                else
                    self.highFiveOutgoing = nil
                end
                self:_setHighFiveNotice(payload.message)
            end
        elseif envelope.type == "highfive_result" then
            if self.ready and payload.sessionId == self.sessionId then
                if payload.receiverId == self.localId then
                    self.highFiveOffers[payload.requestId] = nil
                end
                if payload.initiatorId == self.localId and self.highFiveOutgoing
                    and self.highFiveOutgoing.requestId == payload.requestId
                then
                    self.highFiveOutgoing = nil
                    self:_setHighFiveNotice(payload.message)
                end
            end
        elseif envelope.type == "highfive_start" then
            if self.ready and payload.sessionId == self.sessionId then
                local now = self.clock()
                self.activeHighFives[payload.requestId] = {
                    requestId = payload.requestId,
                    initiatorId = payload.initiatorId,
                    receiverId = payload.receiverId,
                    startedAt = now + payload.startDelayMs / 1000,
                    endsAt = now + payload.startDelayMs / 1000 + Runtime.HIGH_FIVE_ANIMATION_SECONDS,
                }
            end
        elseif envelope.type == "snapshot" then
            if self.ready then self:_applySnapshot(payload) end
        elseif envelope.type == "visitor_snapshot" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > self.lastVisitorTick
            then
                self.lastVisitorTick = payload.serverTick
                self:_queue("visitor_state", {
                    serverTick = payload.serverTick,
                    customer = payload.customer,
                    vendor = payload.vendor,
                })
            end
        elseif envelope.type == "environment_snapshot" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > self.lastEnvironmentTick
            then
                self.lastEnvironmentTick = payload.serverTick
                local employees=payload.employees
                if employees then
                    if payload.serverTick>(self.lastEmployeeTick or -1) then self.lastEmployeeTick=payload.serverTick
                    else employees=nil end
                end
                self:_queue("environment_state", {
                    serverTick = payload.serverTick,
                    bayDoor = payload.bayDoor,
                    truck = payload.truck,
                    employees = employees,
                })
            end
        elseif envelope.type == "employee_snapshot" then
            if self.ready and payload.sessionId==self.sessionId and payload.serverTick>(self.lastEmployeeTick or -1) then
                self.lastEmployeeTick=payload.serverTick
                self:_queue("employee_state",{serverTick=payload.serverTick,employees=payload.employees})
            end
        elseif envelope.type == "pallet_jack_snapshot" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > self.lastPalletJackTick
            then
                self.lastPalletJackTick = payload.serverTick
                self:_queue("pallet_jack_state", {
                    serverTick = payload.serverTick,
                    jack = payload.jack,
                    machines = payload.machines,
                })
            end
        elseif envelope.type == "forklift_snapshot" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > self.lastForkliftTick
            then
                self.lastForkliftTick = payload.serverTick
                self:_queue("forklift_state", {
                    serverTick = payload.serverTick,
                    forklift = payload.forklift,
                })
            end
        elseif envelope.type == "cutter_snapshot" then
            local resourceId = payload.resourceId or "cutter"
            local lastTick = resourceId == "cutter" and self.lastCutterTick
                or (self.lastMachineTicks[resourceId] or -1)
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > lastTick
            then
                if resourceId == "cutter" then self.lastCutterTick = payload.serverTick
                else self.lastMachineTicks[resourceId] = payload.serverTick end
                self.workshopRevisions[resourceId] = math.max(
                    self.workshopRevisions[resourceId] or 0, payload.resourceRevision)
                if self.activeWorkshop and self.activeWorkshop.resourceId == resourceId then
                    self.activeWorkshop.revision = math.max(
                        self.activeWorkshop.revision, payload.resourceRevision)
                end
                self:_queue("cutter_state", {
                    serverTick = payload.serverTick,
                    resourceId = resourceId,
                    resourceRevision = payload.resourceRevision,
                    view = payload.view,
                })
            end
        elseif envelope.type == "windmill_snapshot" then
            local resourceId = payload.resourceId or "windmill"
            local lastTick = resourceId == "windmill" and self.lastWindmillTick
                or (self.lastMachineTicks[resourceId] or -1)
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > lastTick
            then
                if resourceId == "windmill" then self.lastWindmillTick = payload.serverTick
                else self.lastMachineTicks[resourceId] = payload.serverTick end
                self.workshopRevisions[resourceId] = math.max(
                    self.workshopRevisions[resourceId] or 0, payload.resourceRevision)
                if self.activeWorkshop and self.activeWorkshop.resourceId == resourceId then
                    self.activeWorkshop.revision = math.max(
                        self.activeWorkshop.revision, payload.resourceRevision)
                end
                self:_queue("windmill_state", {
                    serverTick = payload.serverTick,
                    resourceId = resourceId,
                    resourceRevision = payload.resourceRevision,
                    view = payload.view,
                })
            end
        elseif envelope.type == "wrapper_snapshot" then
            local resourceId = payload.resourceId
            if self.ready and payload.sessionId == self.sessionId
                and payload.serverTick > (self.lastMachineTicks[resourceId] or -1)
            then
                self.lastMachineTicks[resourceId] = payload.serverTick
                self.workshopRevisions[resourceId] = math.max(
                    self.workshopRevisions[resourceId] or 0, payload.resourceRevision)
                if self.activeWorkshop and self.activeWorkshop.resourceId == resourceId then
                    self.activeWorkshop.revision = math.max(
                        self.activeWorkshop.revision, payload.resourceRevision)
                end
                self:_queue("wrapper_state", {
                    serverTick = payload.serverTick,
                    resourceId = resourceId,
                    resourceRevision = payload.resourceRevision,
                    view = payload.view,
                })
            end
        elseif envelope.type == "interaction_result" then
            local pending = self.pendingInteraction
            if self.ready and payload.sessionId == self.sessionId and pending
                and payload.requestId == pending.requestId
                and payload.targetKind == pending.targetKind
            then
                self.pendingInteraction = nil
                self:_queue("interaction_result", {
                    requestId = payload.requestId,
                    targetKind = payload.targetKind,
                    accepted = payload.accepted,
                    code = payload.code,
                    message = payload.message,
                })
            end
        elseif envelope.type == "workshop_grant" then
            local pending = self.pendingWorkshop
            if self.ready and payload.sessionId == self.sessionId and pending
                and pending.operation == "acquire"
                and payload.requestId == pending.requestId
                and payload.resourceId == pending.resourceId
            then
                self.pendingWorkshop = nil
                local knownRevision = self.workshopRevisions[payload.resourceId] or 0
                local staleGrant = payload.granted and payload.revision < knownRevision
                local granted = payload.granted and not staleGrant
                local acceptedRevision = math.max(knownRevision, payload.revision)
                self.workshopRevisions[payload.resourceId] = acceptedRevision
                if granted then
                    self.activeWorkshop = {
                        resourceId = payload.resourceId,
                        leaseId = payload.leaseId,
                        revision = acceptedRevision,
                    }
                end
                self:_queue("workshop_grant", {
                    requestId = payload.requestId,
                    resourceId = payload.resourceId,
                    granted = granted,
                    leaseId = granted and payload.leaseId or nil,
                    revision = acceptedRevision,
                    code = staleGrant and "stale_grant" or payload.code,
                    message = staleGrant
                        and "Workshop state changed before the control grant arrived. Try again."
                        or payload.message,
                    view = granted and payload.view or nil,
                })
            end
        elseif envelope.type == "workshop_result" then
            local pending = self.pendingWorkshop
            local pendingSafety = self.pendingWorkshopSafety
            local active = self.activeWorkshop
            if self.ready and payload.sessionId == self.sessionId and pendingSafety and active
                and payload.commandId == pendingSafety.commandId
                and payload.resourceId == active.resourceId
                and payload.action == pendingSafety.action
            then
                self.pendingWorkshopSafety = nil
                active.revision = math.max(active.revision, payload.revision)
                self.workshopRevisions[payload.resourceId] = math.max(
                    self.workshopRevisions[payload.resourceId] or 0, payload.revision)
                self:_queue("workshop_result", {
                    commandId = payload.commandId,
                    resourceId = payload.resourceId,
                    action = payload.action,
                    accepted = payload.accepted,
                    revision = payload.revision,
                    code = payload.code,
                    message = payload.message,
                    view = payload.view,
                    urgentSafety = true,
                })
            elseif self.ready and payload.sessionId == self.sessionId and pending and active
                and pending.operation == "command"
                and payload.commandId == pending.commandId
                and payload.resourceId == active.resourceId
                and payload.action == pending.action
            then
                self.pendingWorkshop = nil
                active.revision = math.max(active.revision, payload.revision)
                self.workshopRevisions[payload.resourceId] = math.max(
                    self.workshopRevisions[payload.resourceId] or 0, payload.revision)
                self:_queue("workshop_result", {
                    commandId = payload.commandId,
                    resourceId = payload.resourceId,
                    action = payload.action,
                    accepted = payload.accepted,
                    revision = payload.revision,
                    code = payload.code,
                    message = payload.message,
                    view = payload.view,
                })
            end
        elseif envelope.type == "workshop_snapshot" then
            if self.ready and payload.sessionId == self.sessionId
                and payload.revision > self.lastWorkshopSnapshotRevision
            then
                self.lastWorkshopSnapshotRevision = payload.revision
                local activeRecord, activeRecordAuthoritative
                local workshopResources = {}
                for _, record in ipairs(payload.resources) do
                    self.workshopRevisions[record.resourceId] = math.max(
                        self.workshopRevisions[record.resourceId] or 0, record.revision)
                    workshopResources[#workshopResources + 1] = {
                        resourceId = record.resourceId,
                        occupied = record.occupied == true,
                        ownerPlayerId = record.occupied and record.ownerPlayerId or nil,
                    }
                    if self.activeWorkshop and record.resourceId == self.activeWorkshop.resourceId then
                        activeRecord = record
                        activeRecordAuthoritative = record.revision >= self.activeWorkshop.revision
                        if activeRecordAuthoritative
                            and record.occupied and record.ownerPlayerId == self.localId
                        then
                            self.activeWorkshop.revision = math.max(
                                self.activeWorkshop.revision, record.revision)
                        end
                    end
                end
                self.workshopResources = workshopResources
                if self.activeWorkshop and activeRecordAuthoritative
                    and (not activeRecord.occupied or activeRecord.ownerPlayerId ~= self.localId)
                then
                    local lost = self.activeWorkshop
                    self.activeWorkshop, self.pendingWorkshop, self.pendingWorkshopSafety = nil, nil, nil
                    self:_queue("workshop_lost", {
                        resourceId = lost.resourceId,
                        message = "The host device released this workshop control.",
                    })
                end
                self:_queue("workshop_snapshot", {
                    revision = payload.revision,
                    resources = payload.resources,
                    wrapper = payload.wrapper,
                })
            end
        elseif envelope.type == "pong" then
            local sentAt = self.pendingPing and self.pendingPing[payload.nonce]
            if sentAt then
                self.rtt = math.max(0, (self.clock() - sentAt) * 1000)
                self.pendingPing[payload.nonce] = nil
            end
        elseif envelope.type == "leave" then
            if payload.sessionId ~= self.sessionId then return end
            if payload.playerId == 1 then
                self:_markDisconnected(payload.reason or "The host closed the shop.")
            else
                self:_clearHighFivesForPlayer(payload.playerId)
                self.players[payload.playerId] = nil
                self.lastPlayerTicks[payload.playerId] = math.max(
                    self.lastPlayerTicks[payload.playerId] or -1,
                    payload.serverTick or self.lastServerTick)
                self:_queue("player_left", { playerId = payload.playerId, reason = payload.reason })
            end
        elseif envelope.type == "error" then
            self.status = payload.message
            if self.networkKind == "direct" and (payload.code == "join_rejected"
                or payload.code == "approval_timeout" or payload.code == "kicked"
                or payload.code == "invalid_join" or payload.code == "approval_required")
            then
                self.disconnectReason = payload.message
            end
            self:_queue("error", { code = payload.code, message = payload.message })
        end
    end
end

return Component
