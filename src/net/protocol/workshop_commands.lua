-- Workshop acquisition, command, result, and release validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeWorkshopAcquire(payload)
        local valid, shapeError = Runtime.shape(payload, "workshop_acquire payload",
            { "sessionId", "requestId", "resourceId", "expectedRevision" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "workshop_acquire.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "workshop_acquire.requestId")
        if not requestId then return nil, fieldError end
        local resourceId
        resourceId, fieldError = Runtime.workshopResource(
            payload.resourceId, "workshop_acquire.resourceId")
        if not resourceId then return nil, fieldError end
        local expectedRevision
        expectedRevision, fieldError = Runtime.integerInRange(
            payload.expectedRevision, 0, Runtime.UINT32_MAX, "workshop_acquire.expectedRevision")
        if expectedRevision == nil then return nil, fieldError end
        return {
            sessionId = sessionId,
            requestId = requestId,
            resourceId = resourceId,
            expectedRevision = expectedRevision,
        }
    end

    function Runtime.normalizeWorkshopGrant(payload)
        local valid, shapeError = Runtime.shape(payload, "workshop_grant payload", {
            "sessionId", "requestId", "resourceId", "granted", "code", "message", "revision",
        }, { "leaseId", "view" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "workshop_grant.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "workshop_grant.requestId")
        if not requestId then return nil, fieldError end
        local resourceId
        resourceId, fieldError = Runtime.workshopResource(payload.resourceId, "workshop_grant.resourceId")
        if not resourceId then return nil, fieldError end
        if type(payload.granted) ~= "boolean" then
            return nil, "workshop_grant.granted must be boolean"
        end
        local leaseId
        if payload.leaseId ~= nil then
            leaseId, fieldError = Runtime.token(payload.leaseId, Runtime.MAX_TOKEN_BYTES, "workshop_grant.leaseId")
            if not leaseId then return nil, fieldError end
        end
        if payload.granted ~= (leaseId ~= nil) then
            return nil, "workshop_grant.leaseId must be present exactly when granted"
        end
        local code
        code, fieldError = Runtime.token(payload.code, Runtime.MAX_ERROR_CODE_BYTES, "workshop_grant.code")
        if not code then return nil, fieldError end
        local message
        message, fieldError = Runtime.printableString(
            payload.message, 1, Runtime.MAX_ERROR_MESSAGE_BYTES, "workshop_grant.message")
        if not message then return nil, fieldError end
        local revision
        revision, fieldError = Runtime.integerInRange(
            payload.revision, 0, Runtime.UINT32_MAX, "workshop_grant.revision")
        if revision == nil then return nil, fieldError end
        local normalized = {
            sessionId = sessionId,
            requestId = requestId,
            resourceId = resourceId,
            granted = payload.granted,
            code = code,
            message = message,
            revision = revision,
            leaseId = leaseId,
        }
        if payload.view ~= nil then
            normalized.view, fieldError = Runtime.normalizeWorkshopView(
                payload.view, resourceId, "workshop_grant.view")
            if not normalized.view then return nil, fieldError end
        end
        return normalized
    end

    function Runtime.normalizeWorkshopCommand(payload)
        local valid, shapeError = Runtime.shape(payload, "workshop_command payload", {
            "sessionId", "commandId", "leaseId", "resourceId", "action", "expectedRevision",
        }, {
            "amount", "jobId", "palletId", "programIndex", "gaugeCentiInch", "clamp",
            "barrierClear", "plateId", "setupTask", "setupAction", "itemIndex", "enabled",
            "machineIndex", "placementCell", "callId", "officeIntent", "warehouseIntent",
        })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "workshop_command.sessionId")
        if not sessionId then return nil, fieldError end
        local commandId
        commandId, fieldError = Runtime.integerInRange(
            payload.commandId, 1, Runtime.UINT32_MAX, "workshop_command.commandId")
        if not commandId then return nil, fieldError end
        local leaseId
        leaseId, fieldError = Runtime.token(payload.leaseId, Runtime.MAX_TOKEN_BYTES, "workshop_command.leaseId")
        if not leaseId then return nil, fieldError end
        local resourceId
        resourceId, fieldError = Runtime.workshopResource(payload.resourceId, "workshop_command.resourceId")
        if not resourceId then return nil, fieldError end
        local action, argumentField = Runtime.workshopAction(
            payload.action, resourceId, "workshop_command.action")
        if not action then return nil, argumentField end
        local expectedRevision
        expectedRevision, fieldError = Runtime.integerInRange(
            payload.expectedRevision, 0, Runtime.UINT32_MAX, "workshop_command.expectedRevision")
        if expectedRevision == nil then return nil, fieldError end
        for _, field in ipairs({
            "amount", "jobId", "palletId", "programIndex", "gaugeCentiInch", "clamp",
            "barrierClear", "plateId", "setupTask", "setupAction", "itemIndex", "enabled",
            "machineIndex", "placementCell", "callId", "officeIntent", "warehouseIntent",
        }) do
            local dropCell = resourceId == "pallet_jack" and action == "lower_pallet" and field == "placementCell"
            if field ~= argumentField and not dropCell and payload[field] ~= nil then
                return nil, "workshop_command." .. field .. " is invalid for " .. action
            end
        end
        local normalized = {
            sessionId = sessionId,
            commandId = commandId,
            leaseId = leaseId,
            resourceId = resourceId,
            action = action,
            expectedRevision = expectedRevision,
        }
        if argumentField == "warehouseIntent" then
            normalized.warehouseIntent, fieldError = Runtime.WarehouseIntent.normalize(payload.warehouseIntent)
            if not normalized.warehouseIntent then return nil, fieldError end
            if resourceId == "pallet_jack" and (normalized.warehouseIntent.vehicle ~= "pallet_jack"
                or (normalized.warehouseIntent.kind ~= "store" and normalized.warehouseIntent.kind ~= "retrieve")) then
                return nil, "pallet_jack warehouse actions are limited to its rack transfers"
            end
        elseif argumentField == "officeIntent" then
            normalized.officeIntent, fieldError = Runtime.OfficeIntent.normalize(payload.officeIntent)
            if not normalized.officeIntent then return nil, fieldError end
        elseif argumentField == "amount" then
            normalized.amount, fieldError = Runtime.integerInRange(
                payload.amount, 1, Runtime.MAX_WORKSHOP_AMOUNT, "workshop_command.amount")
            if not normalized.amount then return nil, fieldError end
        elseif argumentField == "programIndex" then
            normalized.programIndex, fieldError = Runtime.integerInRange(
                payload.programIndex, 1, 4, "workshop_command.programIndex")
            if not normalized.programIndex then return nil, fieldError end
        elseif argumentField == "itemIndex" then
            normalized.itemIndex, fieldError = Runtime.integerInRange(
                payload.itemIndex, 1, 16, "workshop_command.itemIndex")
            if not normalized.itemIndex then return nil, fieldError end
        elseif argumentField == "machineIndex" then
            normalized.machineIndex, fieldError = Runtime.integerInRange(
                payload.machineIndex, 1, 3, "workshop_command.machineIndex")
            if not normalized.machineIndex then return nil, fieldError end
        elseif argumentField == "placementCell" then
            normalized.placementCell, fieldError = Runtime.token(
                payload.placementCell, 8, "workshop_command.placementCell")
            if not Runtime.PlacementGrid.decode(normalized.placementCell) then
                return nil, "workshop_command.placementCell is invalid"
            end
        elseif argumentField == "gaugeCentiInch" then
            normalized.gaugeCentiInch, fieldError = Runtime.integerInRange(
                payload.gaugeCentiInch, 0, 2500, "workshop_command.gaugeCentiInch")
            if normalized.gaugeCentiInch == nil then return nil, fieldError end
        elseif argumentField == "clamp" or argumentField == "barrierClear"
            or argumentField == "enabled"
        then
            if type(payload[argumentField]) ~= "boolean" then
                return nil, "workshop_command." .. argumentField .. " must be boolean"
            end
            normalized[argumentField] = payload[argumentField]
        elseif argumentField == "setupTask" then
            if type(payload.setupTask) ~= "string"
                or not Runtime.WORKSHOP_WINDMILL_SETUP_TASKS[payload.setupTask]
            then
                return nil, "workshop_command.setupTask is invalid"
            end
            normalized.setupTask = payload.setupTask
        elseif argumentField == "setupAction" then
            if type(payload.setupAction) ~= "string"
                or not Runtime.WORKSHOP_WINDMILL_SETUP_ACTIONS[payload.setupAction]
            then
                return nil, "workshop_command.setupAction is invalid"
            end
            normalized.setupAction = payload.setupAction
        elseif argumentField then
            normalized[argumentField], fieldError = Runtime.token(
                payload[argumentField], Runtime.MAX_TOKEN_BYTES, "workshop_command." .. argumentField)
            if not normalized[argumentField] then return nil, fieldError end
        end
        if resourceId == "pallet_jack" and action == "lower_pallet" and payload.placementCell ~= nil then
            if not Runtime.PlacementGrid.decode(payload.placementCell) then
                return nil, "workshop_command.placementCell is invalid"
            end
            normalized.placementCell = payload.placementCell
        end
        return normalized
    end

    function Runtime.normalizeWorkshopResult(payload)
        local valid, shapeError = Runtime.shape(payload, "workshop_result payload", {
            "sessionId", "commandId", "resourceId", "action", "accepted", "code", "message",
            "revision",
        }, { "view" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "workshop_result.sessionId")
        if not sessionId then return nil, fieldError end
        local commandId
        commandId, fieldError = Runtime.integerInRange(
            payload.commandId, 1, Runtime.UINT32_MAX, "workshop_result.commandId")
        if not commandId then return nil, fieldError end
        local resourceId
        resourceId, fieldError = Runtime.workshopResource(payload.resourceId, "workshop_result.resourceId")
        if not resourceId then return nil, fieldError end
        local action, actionError = Runtime.workshopAction(
            payload.action, resourceId, "workshop_result.action")
        if not action then return nil, actionError end
        if type(payload.accepted) ~= "boolean" then
            return nil, "workshop_result.accepted must be boolean"
        end
        local code
        code, fieldError = Runtime.token(payload.code, Runtime.MAX_ERROR_CODE_BYTES, "workshop_result.code")
        if not code then return nil, fieldError end
        local message
        message, fieldError = Runtime.printableString(
            payload.message, 1, Runtime.MAX_ERROR_MESSAGE_BYTES, "workshop_result.message")
        if not message then return nil, fieldError end
        local revision
        revision, fieldError = Runtime.integerInRange(
            payload.revision, 0, Runtime.UINT32_MAX, "workshop_result.revision")
        if revision == nil then return nil, fieldError end
        local normalized = {
            sessionId = sessionId,
            commandId = commandId,
            resourceId = resourceId,
            action = action,
            accepted = payload.accepted,
            code = code,
            message = message,
            revision = revision,
        }
        if payload.view ~= nil then
            normalized.view, fieldError = Runtime.normalizeWorkshopView(
                payload.view, resourceId, "workshop_result.view")
            if not normalized.view then return nil, fieldError end
        end
        return normalized
    end

    function Runtime.normalizeWorkshopRelease(payload)
        local valid, shapeError = Runtime.shape(payload, "workshop_release payload",
            { "sessionId", "requestId", "leaseId", "resourceId", "reason" })
        if not valid then return nil, shapeError end
        local sessionId, fieldError = Runtime.token(
            payload.sessionId, Runtime.MAX_TOKEN_BYTES, "workshop_release.sessionId")
        if not sessionId then return nil, fieldError end
        local requestId
        requestId, fieldError = Runtime.integerInRange(
            payload.requestId, 1, Runtime.UINT32_MAX, "workshop_release.requestId")
        if not requestId then return nil, fieldError end
        local leaseId
        leaseId, fieldError = Runtime.token(payload.leaseId, Runtime.MAX_TOKEN_BYTES, "workshop_release.leaseId")
        if not leaseId then return nil, fieldError end
        local resourceId
        resourceId, fieldError = Runtime.workshopResource(payload.resourceId, "workshop_release.resourceId")
        if not resourceId then return nil, fieldError end
        if type(payload.reason) ~= "string" or not Runtime.WORKSHOP_RELEASE_REASONS[payload.reason] then
            return nil, "workshop_release.reason is invalid"
        end
        return {
            sessionId = sessionId,
            requestId = requestId,
            leaseId = leaseId,
            resourceId = resourceId,
            reason = payload.reason,
        }
    end
end

return Component
