-- Client input and reconciliation updates.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}
local TruckMotion = require('src.commute.truck_motion')

local function smoothCommuteMotion(player,dt)
    local target=player and player._targetRecord
    if not target or target.sceneId~='commute' then
        if player then
            player._visualVelocityX,player._visualVelocityY=nil,nil
            player._visualIntentX,player._visualIntentY=nil,nil
            player._visualWalkDistance=nil
        end
        return
    end
    local alpha=math.min(1,math.max(0,dt)*20)
    local vx,vy=target.velocityX or 0,target.velocityY or 0
    if player._visualVelocityX==nil then
        player._visualVelocityX,player._visualVelocityY=vx,vy
    else
        player._visualVelocityX=player._visualVelocityX+(vx-player._visualVelocityX)*alpha
        player._visualVelocityY=player._visualVelocityY+(vy-player._visualVelocityY)*alpha
    end
    local distance=math.max(0,target.animationDistance or 0)/48
    if player._visualWalkDistance==nil then player._visualWalkDistance=distance
    else
        local speed=math.sqrt(player._visualVelocityX^2+player._visualVelocityY^2)
        player._visualWalkDistance=player._visualWalkDistance+speed*math.max(0,dt)
        player._visualWalkDistance=player._visualWalkDistance+(distance-player._visualWalkDistance)*alpha
    end
    local ix,iy=target.intentX or 0,target.intentY or 0
    if ix*ix+iy*iy>.01 then
        local wanted=math.atan2(iy,ix)
        local current=player._visualIntentX and player._visualIntentY
            and math.atan2(player._visualIntentY,player._visualIntentX) or wanted
        local delta=math.atan2(math.sin(wanted-current),math.cos(wanted-current))
        current=current+delta*alpha
        player._visualIntentX,player._visualIntentY=math.cos(current),math.sin(current)
    end
end

function Component.install(Runtime)
    Runtime.CLIENT_PING_INTERVAL=2
    Runtime.CLIENT_PING_TIMEOUT=6

    function Runtime.Session:_updateClientPing(dt)
        if not self:isClient() or self.terminal or not self.ready or not self.sessionId then return end
        local now=self.clock()
        if not Runtime.finite(now) then return end
        for nonce,sentAt in pairs(self.pendingPing or {}) do
            if now-sentAt>Runtime.CLIENT_PING_TIMEOUT then
                self.pendingPing[nonce]=nil
                self.pingLostCount=(self.pingLostCount or 0)+1
            end
        end
        self.pingAccumulator=(self.pingAccumulator or 0)+math.max(0,dt or 0)
        if self.pingAccumulator<Runtime.CLIENT_PING_INTERVAL then return end
        self.pingAccumulator=self.pingAccumulator%Runtime.CLIENT_PING_INTERVAL
        self.pingNonce=((self.pingNonce or 0)+1)%4294967296
        local nonce=self.pingNonce
        local okay=self:_sendToServer('ping',{sessionId=self.sessionId,nonce=nonce})
        if okay then
            self.pendingPing=self.pendingPing or {}
            self.pendingPing[nonce]=now
            self.lastPingSentAt=now
            self.pingSentCount=(self.pingSentCount or 0)+1
        else
            self.pingSendFailures=(self.pingSendFailures or 0)+1
        end
    end

    function Runtime.Session:_sendClientInput(dt, context)
        if not self.ready or not self.sessionId then return end
        self.inputAccumulator = self.inputAccumulator + dt
        local riding=context and context.localPlayer and context.localPlayer.sceneId=='commute'
        -- Dispatch discrete control edges this frame. Analog variation within
        -- a direction still uses the normal input rate.
        local function direction(value)
            return value and (value > .1 and 1 or value < -.1 and -1) or 0
        end
        local changed=riding and (direction(context.inputX)~=direction(self.sentRideX)
            or direction(context.inputY)~=direction(self.sentRideY) or context.inputBoost~=self.sentRideBoost)
        if not changed and self.inputAccumulator < Runtime.INPUT_INTERVAL then return end
        self.inputAccumulator = changed and 0 or self.inputAccumulator % Runtime.INPUT_INTERVAL
        if riding then self.sentRideX,self.sentRideY,self.sentRideBoost=context.inputX,context.inputY,context.inputBoost end
        self.inputSequence = self.inputSequence + 1
        local ok, errorMessage = self:_sendToServer("input", {
            sessionId = self.sessionId,
            sequence = self.inputSequence,
            name = self.localName,
            moveX = Runtime.clamp(context and context.inputX, -1, 1),
            moveY = Runtime.clamp(context and context.inputY, -1, 1),
            boost = context and context.inputBoost == true or false,
            gameX = Runtime.clamp(context and context.gameX, -1, 1),
            gameY = Runtime.clamp(context and context.gameY, -1, 1),
            combatButtons = context and context.combatButtons or 0,
            arcade = context and context.arcade,
            furColorway = context and context.localPlayer and context.localPlayer.furColorway
                or self.localFurColorway or 1,
            overallsColorway = context and context.localPlayer and context.localPlayer.overallsColorway
                or self.localOverallsColorway or 1,
            taskAction = context and context.localPlayer and context.localPlayer.taskAction or "none",
        })
        if ok and changed and self.transport.flush then self.transport:flush() end
        if not ok then self:_queue("error", { message = errorMessage }) end
    end

    function Runtime.Session:_updateClientVisuals(dt, context)
        if not self.ready then return end
        local localPlayer=context and context.localPlayer
        for _,player in pairs(self.players) do
            smoothCommuteMotion(player,dt)
            if player._snapshotAge then
                player._snapshotAge=player._snapshotAge+dt
                if player._snapshotAge>.3 then player._rideMotion=nil;player._truckMotion=nil end
            end
            TruckMotion.update(player,dt)
        end
        local function lead(player)
            if not player or not player._snapshotAge then return 0,0 end
            local age=math.min(.12,player._snapshotAge)
            local vx,vy=player._rideVX,player._rideVY
            local target=player._targetRecord
            if target and target.sceneId~='commute' then
                vx,vy=target.velocityX or 0,target.velocityY or 0
            end
            return vx*age,vy*age
        end
        if localPlayer and self.localTarget then
            if (localPlayer.sceneId or "warehouse")~=(self.localTarget.sceneId or "warehouse")
                or (localPlayer.resting==true)~=(self.localTarget.resting==true) then
                Runtime.copyMotion(localPlayer,self.localTarget,true)
            end
            localPlayer.resting=self.localTarget.resting==true
            local own=self.players[self.localId]
            localPlayer._rideMotion=own and own._rideMotion
            localPlayer._visualTruckMotion=own and own._visualTruckMotion
            localPlayer._visualVelocityX=own and own._visualVelocityX
            localPlayer._visualVelocityY=own and own._visualVelocityY
            localPlayer._visualIntentX=own and own._visualIntentX
            localPlayer._visualIntentY=own and own._visualIntentY
            localPlayer._visualWalkDistance=own and own._visualWalkDistance
            local lx,ly=lead(own)
            local dx = self.localTarget.x + lx - localPlayer.x
            local dy = self.localTarget.y + ly - localPlayer.y
            local distanceSquared = dx * dx + dy * dy
            if distanceSquared > Runtime.TELEPORT_DISTANCE * Runtime.TELEPORT_DISTANCE then
                localPlayer.x, localPlayer.y = self.localTarget.x, self.localTarget.y
            else
                local alpha = math.min(1, math.max(0, dt) * Runtime.CORRECTION_RATE)
                localPlayer.x, localPlayer.y = localPlayer.x + dx * alpha, localPlayer.y + dy * alpha
            end
        end
        local alpha = math.min(1, math.max(0, dt) * Runtime.REMOTE_SMOOTH_RATE)
        for id, player in pairs(self.players) do
            if id ~= self.localId and player._targetRecord then
                local startX, startY = player.x, player.y
                local lx,ly=lead(player)
                player.x = player.x + (player._targetX + lx - player.x) * alpha
                player.y = player.y + (player._targetY + ly - player.y) * alpha
                local dx, dy = player.x - startX, player.y - startY
                local distance = math.sqrt(dx * dx + dy * dy)
                Runtime.copyMotion(player, player._targetRecord, false)
                if distance > 0.001 then
                    player.animationDistance = (player.animationDistance or 0) + distance
                    player.idleClock = 0
                    player.moving = true
                else
                    player.idleClock = (player.idleClock or 0) + dt
                    player.moving = player._targetRecord.moving == true
                end
            end
        end
    end

    function Runtime.Session:_updateClientHighFives()
        local now = self.clock()
        for requestId, offer in pairs(self.highFiveOffers) do
            if not Runtime.finite(now) or now >= offer.expiresAt then
                self.highFiveOffers[requestId] = nil
            end
        end
        for requestId, active in pairs(self.activeHighFives) do
            if not Runtime.finite(now) or now >= active.endsAt then
                self.activeHighFives[requestId] = nil
            end
        end
        if self.highFiveNotice and (not Runtime.finite(now) or now >= self.highFiveNotice.expiresAt) then
            self.highFiveNotice = nil
        end
        if self.highFiveOutgoing and Runtime.finite(now) and now >= self.highFiveOutgoing.expiresAt then
            self.highFiveOutgoing = nil
        end
    end

    function Runtime.Session:update(dt, context)
        if not self:isActive() or self.terminal then return end
        dt = math.max(0, math.min(tonumber(dt) or 0, 0.25))
        if self.mode == "host" then self:_syncLocalPlayer(context and context.localPlayer) end
        if not self:_service(context) then return end
        if self.mode == "host" then
            self:_updateHost(dt, context)
        else
            if self.pendingInteraction
                and self.clock() - self.pendingInteraction.sentAt > Runtime.INTERACTION_TIMEOUT
            then
                local timedOut = self.pendingInteraction
                self.pendingInteraction = nil
                self:_queue("interaction_result", {
                    requestId = timedOut.requestId,
                    targetKind = timedOut.targetKind,
                    accepted = false,
                    code = "timeout",
                    message = "The host device did not answer. The switch is safe to try again.",
                })
            end
            if self.pendingWorkshop
                and self.clock() - self.pendingWorkshop.sentAt > Runtime.WORKSHOP_TIMEOUT
            then
                local timedOut = self.pendingWorkshop
                self.pendingWorkshop = nil
                if timedOut.operation == "acquire" then
                    self:_queue("workshop_grant", {
                        requestId = timedOut.requestId,
                        resourceId = timedOut.resourceId,
                        granted = false,
                        code = "timeout",
                        message = "The host device did not answer the workshop request.",
                        revision = self.workshopRevisions[timedOut.resourceId] or 0,
                    })
                else
                    self:_queue("workshop_result", {
                        commandId = timedOut.commandId,
                        resourceId = timedOut.resourceId,
                        action = timedOut.action,
                        accepted = false,
                        code = "timeout",
                        message = "The host device did not answer the workshop action.",
                        revision = self.workshopRevisions[timedOut.resourceId] or 0,
                    })
                end
            end
            if self.pendingWorkshopSafety
                and self.clock() - self.pendingWorkshopSafety.sentAt > Runtime.WORKSHOP_TIMEOUT
            then
                local timedOut = self.pendingWorkshopSafety
                self.pendingWorkshopSafety = nil
                self:_queue("workshop_result", {
                    commandId = timedOut.commandId,
                    resourceId = timedOut.resourceId,
                    action = timedOut.action,
                    accepted = false,
                    code = "timeout",
                    message = "The host did not answer the urgent workshop safety action.",
                    revision = self.workshopRevisions[timedOut.resourceId] or 0,
                    urgentSafety = true,
                })
            end
            if not self.ready and self.connectedAt
                and self.clock() - self.connectedAt > self.clientConnectTimeout
            then
                local timeoutMessage = self.networkKind == "direct"
                    and "Connection timed out. Check the Direct host address and network route."
                    or "Connection timed out. Check the host IPv4 address, same local subnet, and whether the hotspot allows devices to reach each other."
                self:_markDisconnected(timeoutMessage)
                self:_closeTransport(1, true)
                return
            end
            self:_sendClientInput(dt, context)
            self:_updateClientPing(dt)
            self:_updateClientVisuals(dt,context)
            self:_updateClientHighFives()
        end
    end

    function Runtime.Session:sendNeutralInput()
        if not self:isClient() or self.terminal or not self.ready or not self.sessionId then return false end
        self.inputSequence = self.inputSequence + 1
        return self:_sendToServer("input", {
            sessionId = self.sessionId,
            sequence = self.inputSequence,
            moveX = 0,
            moveY = 0,
            boost = false,
            furColorway = self.localFurColorway or 1,
            overallsColorway = self.localOverallsColorway or 1,
            taskAction = self.localTaskAction or "none",
        })
    end

    function Runtime.Session:requestHighFive(targetId)
        targetId = tonumber(targetId)
        if not self:isActive() or self.terminal or not self.ready or not self.sessionId then
            return false, "Join an online game before asking for a high five."
        end
        if not targetId or targetId ~= math.floor(targetId)
            or targetId < 1 or targetId > Runtime.Protocol.MAX_PLAYERS
            or targetId == self.localId or not self.players[targetId]
        then
            return false, "That player is no longer available."
        end
        if self:isHost() then
            return self:_createHighFive(self.localId, targetId)
        end
        if self.highFiveOutgoing then
            return false, "Wait for your current high-five request to finish."
        end
        self.highFiveClientRequestId = self.highFiveClientRequestId % 4294967295 + 1
        local requestId = self.highFiveClientRequestId
        local ok, errorMessage = self:_sendToServer("highfive_request", {
            sessionId = self.sessionId,
            requestId = requestId,
            targetId = targetId,
        })
        if not ok then return false, errorMessage end
        self.highFiveOutgoing = {
            clientRequestId = requestId,
            targetId = targetId,
            status = "sending",
            expiresAt = self.clock() + Runtime.HIGH_FIVE_OFFER_SECONDS + 2,
        }
        self:_setHighFiveNotice("Sending high-five request...")
        return true
    end

    function Runtime.Session:respondHighFive(requestId, accepted)
        requestId = tonumber(requestId)
        if not self:isActive() or self.terminal or not self.ready or not self.sessionId then
            return false, "The online session is no longer active."
        end
        local offer = requestId and self.highFiveOffers[requestId]
        if not offer or offer.receiverId ~= self.localId then
            return false, "That high-five request has expired."
        end
        accepted = accepted == true
        if self:isHost() then
            return self:_resolveHighFive(requestId, self.localId, accepted)
        end
        local ok, errorMessage = self:_sendToServer("highfive_response", {
            sessionId = self.sessionId,
            requestId = requestId,
            accepted = accepted,
        })
        if not ok then return false, errorMessage end
        self.highFiveOffers[requestId] = nil
        self:_setHighFiveNotice(accepted and "High five accepted!" or "High five declined.")
        return true
    end

    function Runtime.Session:highFiveInfo()
        local now = self.clock()
        local offers = {}
        for requestId, offer in pairs(self.highFiveOffers) do
            if Runtime.finite(now) and now < offer.expiresAt then
                offers[#offers + 1] = {
                    requestId = requestId,
                    initiatorId = offer.initiatorId,
                    initiatorName = offer.initiatorName,
                    expiresIn = offer.expiresAt - now,
                }
            end
        end
        table.sort(offers, function(left, right) return left.requestId < right.requestId end)
        local notice = self.highFiveNotice
        if notice and (not Runtime.finite(now) or now >= notice.expiresAt) then notice = nil end
        local outgoing = self.highFiveOutgoing
        if outgoing and Runtime.finite(now) and now >= outgoing.expiresAt then outgoing = nil end
        return {
            active = self:isActive() and self.ready and not self.terminal,
            offers = offers,
            notice = notice and notice.message or nil,
            outgoing = outgoing and outgoing.status or nil,
        }
    end

    function Runtime.Session:highFiveAnimationFor(playerId)
        playerId = tonumber(playerId)
        if not playerId or not self:isActive() or not self.ready or self.terminal then return nil end
        local now = self.clock()
        if not Runtime.finite(now) then return nil end
        for requestId, active in pairs(self.activeHighFives) do
            if now >= active.startedAt and now < active.endsAt
                and (active.initiatorId == playerId or active.receiverId == playerId)
            then
                local partnerId = active.initiatorId == playerId
                    and active.receiverId or active.initiatorId
                local partner = self.players[partnerId]
                return {
                    requestId = requestId,
                    partnerId = partnerId,
                    partnerX = partner and partner.x or nil,
                    elapsed = now - active.startedAt,
                    duration = Runtime.HIGH_FIVE_ANIMATION_SECONDS,
                }
            end
        end
        return nil
    end

    function Runtime.Session:requestInteraction(targetKind, desiredState,shotAim,signature)
        if not self:isClient() or self.terminal or not self.ready or not self.sessionId then
            return false, "This worker device is not ready to interact with the host shop."
        end
        if self.pendingInteraction then
            return false, "Waiting for the host to answer the previous request."
        end
        self.interactionRequestId = self.interactionRequestId + 1
        local request = {
            sessionId = self.sessionId,
            requestId = self.interactionRequestId,
            targetKind = targetKind,
            desiredState = desiredState,
            shotAim = shotAim,
            signature = signature,
        }
        local ok, errorMessage = self:_sendToServer("interaction_request", request)
        if not ok then return false, errorMessage end
        self.pendingInteraction = {
            requestId = request.requestId,
            targetKind = request.targetKind,
            desiredState = request.desiredState,
            sentAt = self.clock(),
        }
        return true
    end

    function Runtime.Session:publishRadioState(state)
        if not self:isHost() or self.terminal or not self.ready or not self.sessionId then
            return false, "Only the active host can broadcast the shop radio."
        end
        if type(state) ~= "table" then return false, "The shop radio state is invalid." end
        if self.radioRevision >= 4294967295 then self.radioRevision = 0 end
        self.radioRevision = self.radioRevision + 1
        self.radioState = {
            trackIndex = state.trackIndex,
            active = state.active,
            paused = state.paused,
            muted = state.muted,
            positionMs = state.positionMs,
        }
        return self:_broadcastJoined("radio_state", {
            sessionId = self.sessionId,
            revision = self.radioRevision,
            trackIndex = self.radioState.trackIndex,
            active = self.radioState.active,
            paused = self.radioState.paused,
            muted = self.radioState.muted,
            positionMs = self.radioState.positionMs,
        })
    end

    function Runtime.Session:requestWorkshopAcquire(resourceId)
        if not self:isClient() or self.terminal or not self.ready or not self.sessionId then
            return false, "This worker device is not ready to use the host shop."
        end
        if self.pendingWorkshop then
            return false, "Waiting for the host to answer the previous workshop request."
        end
        if self.activeWorkshop then
            return false, "Close the current remote console before using another one."
        end
        self.workshopRequestId = self.workshopRequestId + 1
        local request = {
            sessionId = self.sessionId,
            requestId = self.workshopRequestId,
            resourceId = resourceId,
            expectedRevision = self.workshopRevisions[resourceId] or 0,
        }
        local ok, errorMessage = self:_sendToServer("workshop_acquire", request)
        if not ok then return false, errorMessage end
        self.pendingWorkshop = {
            operation = "acquire",
            requestId = request.requestId,
            resourceId = resourceId,
            sentAt = self.clock(),
        }
        return true
    end
end

return Component
