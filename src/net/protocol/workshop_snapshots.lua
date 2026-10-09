-- Workshop resources, pallet-jack, and machine snapshots.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeWorkshopResources(value, label)
        if not Runtime.Codec.isArray(value) then return nil, label .. " must be an array" end
        if #value < 10 or #value > 24 then
            return nil, label .. " must contain 10 to 24 workshop resources"
        end
        local resources, seen = {}, {}
        for index = 1, #value do
            local resourceLabel = label .. "[" .. index .. "]"
            local valid, shapeError = Runtime.shape(value[index], resourceLabel,
                { "resourceId", "revision", "occupied" }, { "ownerPlayerId" })
            if not valid then return nil, shapeError end
            local resourceId, fieldError = Runtime.workshopResource(
                value[index].resourceId, resourceLabel .. ".resourceId")
            if not resourceId then return nil, fieldError end
            if seen[resourceId] then return nil, label .. " contains a duplicate resourceId" end
            seen[resourceId] = true
            local revision
            revision, fieldError = Runtime.integerInRange(
                value[index].revision, 0, Runtime.UINT32_MAX, resourceLabel .. ".revision")
            if revision == nil then return nil, fieldError end
            if type(value[index].occupied) ~= "boolean" then
                return nil, resourceLabel .. ".occupied must be boolean"
            end
            local ownerPlayerId
            if value[index].ownerPlayerId ~= nil then
                ownerPlayerId, fieldError = Runtime.integerInRange(
                    value[index].ownerPlayerId, 1, Runtime.Protocol.MAX_PLAYERS,
                    resourceLabel .. ".ownerPlayerId")
                if not ownerPlayerId then return nil, fieldError end
            end
            if value[index].occupied ~= (ownerPlayerId ~= nil) then
                return nil, resourceLabel .. ".ownerPlayerId must be present exactly when occupied"
            end
            resources[#resources + 1] = {
                resourceId = resourceId,
                revision = revision,
                occupied = value[index].occupied,
                ownerPlayerId = ownerPlayerId,
            }
        end
        for resourceId in pairs(Runtime.WORKSHOP_RESOURCES) do
            if not seen[resourceId] then return nil, label .. " is missing " .. resourceId end
        end
        table.sort(resources, function(a, b) return a.resourceId < b.resourceId end)
        return Runtime.Codec.array(resources)
    end

    Runtime.PALLET_JACK_DIRECTIONS = {
        northwest = true, north = true, northeast = true, east = true,
        southeast = true, south = true, southwest = true, west = true,
    }

    function Runtime.normalizePalletJackState(value, label)
        local valid, shapeError = Runtime.shape(value, label,
            { "x", "y", "direction", "operating", "moving" },
            { "operatorPlayerId", "operatorEmployeeId", "carriedPalletId", "candidatePalletId", "sceneId" })
        if not valid then return nil, shapeError end
        local x, fieldError = Runtime.numberInRange(
            value.x, -Runtime.MAX_COORDINATE, Runtime.MAX_COORDINATE, label .. ".x")
        if x == nil then return nil, fieldError end
        local y
        y, fieldError = Runtime.numberInRange(
            value.y, -Runtime.MAX_COORDINATE, Runtime.MAX_COORDINATE, label .. ".y")
        if y == nil then return nil, fieldError end
        if type(value.direction) ~= "string" or not Runtime.PALLET_JACK_DIRECTIONS[value.direction] then
            return nil, label .. ".direction is invalid"
        end
        local sceneId=value.sceneId or "warehouse"
        if sceneId~="warehouse" and sceneId~="front_left" and sceneId~="front_right" then
            return nil,label..".sceneId is invalid"
        end
        if type(value.operating) ~= "boolean" then
            return nil, label .. ".operating must be boolean"
        end
        if type(value.moving) ~= "boolean" then
            return nil, label .. ".moving must be boolean"
        end
        if value.moving and not value.operating then
            return nil, label .. ".moving requires an operator"
        end
        local operatorPlayerId
        if value.operatorPlayerId ~= nil then
            operatorPlayerId, fieldError = Runtime.integerInRange(
                value.operatorPlayerId, 1, Runtime.Protocol.MAX_PLAYERS, label .. ".operatorPlayerId")
            if not operatorPlayerId then return nil, fieldError end
        end
        local operatorEmployeeId = value.operatorEmployeeId
        if operatorEmployeeId ~= nil and (type(operatorEmployeeId) ~= "string" or #operatorEmployeeId > 16
            or not operatorEmployeeId:match("^EMP%-%d+$")) then
            return nil, label .. ".operatorEmployeeId is invalid"
        end
        if operatorEmployeeId and operatorPlayerId then return nil, label .. " has two operators" end
        if value.operating ~= (operatorPlayerId ~= nil or operatorEmployeeId ~= nil) then
            return nil, label .. " must have exactly one operator when operating"
        end
        local carriedPalletId
        if value.carriedPalletId ~= nil then
            carriedPalletId, fieldError = Runtime.token(
                value.carriedPalletId, Runtime.MAX_TOKEN_BYTES, label .. ".carriedPalletId")
            if not carriedPalletId then return nil, fieldError end
        end
        local candidatePalletId
        if value.candidatePalletId ~= nil then
            candidatePalletId, fieldError = Runtime.token(
                value.candidatePalletId, Runtime.MAX_TOKEN_BYTES, label .. ".candidatePalletId")
            if not candidatePalletId then return nil, fieldError end
            if not value.operating or carriedPalletId then
                return nil, label .. ".candidatePalletId requires an operating empty jack"
            end
        end
        return {
            x = x,
            y = y,
            direction = value.direction,
            sceneId = sceneId,
            operating = value.operating,
            moving = value.moving,
            operatorPlayerId = operatorPlayerId,
            operatorEmployeeId = operatorEmployeeId,
            carriedPalletId = carriedPalletId,
            candidatePalletId = candidatePalletId,
        }
    end

    function Runtime.normalizePalletJackSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "pallet_jack_snapshot payload",
            { "sessionId", "serverTick", "jack", "machines" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "pallet_jack_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(
            payload.serverTick, 0, Runtime.UINT32_MAX, "pallet_jack_snapshot.serverTick")
        if serverTick == nil then return nil, fieldError end
        local jack
        jack, fieldError = Runtime.normalizePalletJackState(
            payload.jack, "pallet_jack_snapshot.jack")
        if not jack then return nil, fieldError end
        local machines
        machines, fieldError = Runtime.MachinePose.normalize(
            payload.machines, jack, Runtime.MAX_COORDINATE, "pallet_jack_snapshot.machines")
        if not machines then return nil, fieldError end
        return {
            sessionId = sessionId,
            serverTick = serverTick,
            jack = jack,
            machines = machines,
        }
    end

    function Runtime.normalizeWorkshopSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "workshop_snapshot payload",
            { "sessionId", "revision", "resources", "wrapper" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "workshop_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local revision
        revision, fieldError = Runtime.integerInRange(
            payload.revision, 0, Runtime.UINT32_MAX, "workshop_snapshot.revision")
        if revision == nil then return nil, fieldError end
        local resources
        resources, fieldError = Runtime.normalizeWorkshopResources(
            payload.resources, "workshop_snapshot.resources")
        if not resources then return nil, fieldError end
        local wrapper
        wrapper, fieldError = Runtime.normalizeWorkshopWrapperRuntime(
            payload.wrapper, "workshop_snapshot.wrapper")
        if not wrapper then return nil, fieldError end
        return {
            sessionId = sessionId,
            revision = revision,
            resources = resources,
            wrapper = wrapper,
        }
    end

    function Runtime.normalizeCutterSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "cutter_snapshot payload",
            { "sessionId", "serverTick", "resourceRevision", "view" }, { "resourceId" })
        if not valid then return nil, shapeError end
        local resourceId = payload.resourceId or "cutter"
        if Runtime.MachineResource.parse(resourceId) ~= "cutter" then
            return nil, "cutter_snapshot.resourceId is invalid"
        end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "cutter_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(
            payload.serverTick, 0, Runtime.UINT32_MAX, "cutter_snapshot.serverTick")
        if serverTick == nil then return nil, fieldError end
        local resourceRevision
        resourceRevision, fieldError = Runtime.integerInRange(
            payload.resourceRevision, 0, Runtime.UINT32_MAX, "cutter_snapshot.resourceRevision")
        if resourceRevision == nil then return nil, fieldError end
        local view
        view, fieldError = Runtime.normalizeCutterWorkshopView(
            payload.view, "cutter_snapshot.view")
        if not view then return nil, fieldError end
        return {
            sessionId = sessionId,
            serverTick = serverTick,
            resourceRevision = resourceRevision,
            resourceId = resourceId,
            view = view,
        }
    end

    function Runtime.normalizeWrapperSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "wrapper_snapshot payload",
            { "sessionId", "serverTick", "resourceId", "resourceRevision", "view" })
        if not valid then return nil, shapeError end
        if Runtime.MachineResource.parse(payload.resourceId) ~= "skid_wrapper" then
            return nil, "wrapper_snapshot.resourceId is invalid"
        end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "wrapper_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(
            payload.serverTick, 0, Runtime.UINT32_MAX, "wrapper_snapshot.serverTick")
        if serverTick == nil then return nil, fieldError end
        local resourceRevision
        resourceRevision, fieldError = Runtime.integerInRange(
            payload.resourceRevision, 0, Runtime.UINT32_MAX, "wrapper_snapshot.resourceRevision")
        if resourceRevision == nil then return nil, fieldError end
        local view
        view, fieldError = Runtime.normalizeWorkshopWrapperRuntime(
            payload.view, "wrapper_snapshot.view")
        if not view then return nil, fieldError end
        return {
            sessionId = sessionId, serverTick = serverTick,
            resourceId = payload.resourceId, resourceRevision = resourceRevision,
            view = view,
        }
    end

    function Runtime.normalizeWindmillSnapshot(payload)
        local valid, shapeError = Runtime.shape(payload, "windmill_snapshot payload",
            { "sessionId", "serverTick", "resourceRevision", "view" }, { "resourceId" })
        if not valid then return nil, shapeError end
        local resourceId = payload.resourceId or "windmill"
        if Runtime.MachineResource.parse(resourceId) ~= "windmill" then
            return nil, "windmill_snapshot.resourceId is invalid"
        end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "windmill_snapshot.sessionId")
        if not sessionId then return nil, fieldError end
        local serverTick
        serverTick, fieldError = Runtime.integerInRange(
            payload.serverTick, 0, Runtime.UINT32_MAX, "windmill_snapshot.serverTick")
        if serverTick == nil then return nil, fieldError end
        local resourceRevision
        resourceRevision, fieldError = Runtime.integerInRange(
            payload.resourceRevision, 0, Runtime.UINT32_MAX, "windmill_snapshot.resourceRevision")
        if resourceRevision == nil then return nil, fieldError end
        local view
        view, fieldError = Runtime.normalizeWindmillWorkshopView(
            payload.view, "windmill_snapshot.view")
        if not view then return nil, fieldError end
        return {
            sessionId = sessionId,
            serverTick = serverTick,
            resourceRevision = resourceRevision,
            resourceId = resourceId,
            view = view,
        }
    end
end

return Component
