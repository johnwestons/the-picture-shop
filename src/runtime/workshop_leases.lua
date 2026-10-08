-- Local workshop leases and session cleanup.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.localAuthorityPlayer()
        return {
            id = 1,
            sceneId = Runtime.World.player.sceneId,
            x = Runtime.World.player.x,
            y = Runtime.World.player.y,
            intentX = Runtime.World.player.intentX,
            intentY = Runtime.World.player.intentY,
            facing = Runtime.World.player.facing,
        }
    end

    function Runtime.acquireLocalWorkshop(resourceId)
        if not Runtime.workshopAuthority then return false, "Workshop authority is unavailable." end
        Runtime.localWorkshopRequestId = Runtime.localWorkshopRequestId + 1
        local result = Runtime.workshopAuthority:acquire(Runtime.localAuthorityPlayer(), {
            requestId = Runtime.localWorkshopRequestId,
            resourceId = resourceId,
        }, { state = Runtime.state })
        if result.accepted then Runtime.localWorkshopLease = result end
        return result.accepted, result.message
    end

    function Runtime.commandLocalWorkshop(action, arguments)
        if not Runtime.workshopAuthority or not Runtime.localWorkshopLease then
            return false, "No host-authorized workshop control is active."
        end
        Runtime.localWorkshopRequestId = Runtime.localWorkshopRequestId + 1
        local result = Runtime.workshopAuthority:command(Runtime.localAuthorityPlayer(), {
            requestId = Runtime.localWorkshopRequestId,
            resourceId = Runtime.localWorkshopLease.resourceId,
            leaseId = Runtime.localWorkshopLease.leaseId,
            action = action,
            args = type(arguments) == "table" and arguments or {},
            expectedRevision = Runtime.localWorkshopLease.revision,
        }, { state = Runtime.state })
        if result.accepted then Runtime.localWorkshopLease.revision = result.revision end
        return result.accepted, result.message, result
    end

    function Runtime.releaseLocalWorkshop(reason)
        if not Runtime.workshopAuthority or not Runtime.localWorkshopLease then return false end
        Runtime.localWorkshopRequestId = Runtime.localWorkshopRequestId + 1
        local result = Runtime.workshopAuthority:release(Runtime.localAuthorityPlayer(), {
            requestId = Runtime.localWorkshopRequestId,
            resourceId = Runtime.localWorkshopLease.resourceId,
            leaseId = Runtime.localWorkshopLease.leaseId,
            reason = reason == "cancelled" and "cancelled" or "closed",
        }, { state = Runtime.state })
        Runtime.localWorkshopLease = nil
        Runtime.state._localWorkshopMachineId = nil
        return result.accepted
    end

    function Runtime.clearWorkshopAuthority(reason)
        if Runtime.workshopAuthority then
            for playerId = 1, 4 do
                Runtime.workshopAuthority:cleanupPlayer({ id = playerId }, reason or "session_closed",
                    { state = Runtime.state })
            end
        end
        Runtime.workshopAuthority = nil
        Runtime.localWorkshopLease = nil
        Runtime.state._localWorkshopMachineId = nil
        Runtime.activeCutterRemote = nil
        Runtime.cutterMaintenanceAuthority = nil
        Runtime.activeWrapperRemote = nil
        Runtime.wrapperMaintenanceAuthority = nil
        Runtime.activeWindmillRemote = nil
        Runtime.machineRemoteSessions = {}
    end
end

return Component
