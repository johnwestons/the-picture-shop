-- Warehouse controls and authority intents.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.warehousePlayer()
        return {id=Runtime.World.player.id or 1,x=Runtime.World.player.x,y=Runtime.World.player.y,
            sceneId=Runtime.World.player.sceneId or "warehouse"}
    end

    function Runtime.sendWarehouseIntent(intent)
        local function refused(message)
            Runtime.state.message=message or "The warehouse action could not be sent."
            return false,Runtime.state.message
        end
        if Runtime.multiplayer:isClient() then
            if Runtime.warehousePendingIntent then return refused("Wait for the host to finish the current warehouse action.") end
            Runtime.warehousePendingIntent=intent
            local info=Runtime.multiplayer:workshopInfo()
            local jackTransfer=info and info.resourceId=="pallet_jack"
                and intent.vehicle=="pallet_jack" and (intent.kind=="store" or intent.kind=="retrieve")
            local sent,message
            if info and (info.resourceId=="warehouse" or jackTransfer) then
                sent,message=Runtime.multiplayer:requestWorkshopCommand("warehouse_action",{warehouseIntent=intent})
            elseif info then
                Runtime.warehousePendingIntent=nil
                return refused("Close or park the other workshop control first.")
            else sent,message=Runtime.multiplayer:requestWorkshopAcquire("warehouse") end
            if not sent then Runtime.warehousePendingIntent=nil; return refused(message) end
            Runtime.state.message="Waiting for the host to confirm the warehouse action..."
            return nil
        end
        local accepted,message,result
        if Runtime.multiplayer:isHost() then
            local jackTransfer=Runtime.localWorkshopLease and Runtime.localWorkshopLease.resourceId=="pallet_jack"
                and intent.vehicle=="pallet_jack" and (intent.kind=="store" or intent.kind=="retrieve")
            if not Runtime.localWorkshopLease or (Runtime.localWorkshopLease.resourceId~="warehouse" and not jackTransfer) then
                if Runtime.localWorkshopLease then return refused("Close or park the other workshop control first.") end
                accepted,message=Runtime.acquireLocalWorkshop("warehouse")
                if not accepted then Runtime.state.message=message; return false,message end
            end
            accepted,message,result=Runtime.commandLocalWorkshop("warehouse_action",{warehouseIntent=intent})
            if accepted and intent.kind=="release" then Runtime.releaseLocalWorkshop("closed") end
            if not accepted and intent.kind=="operate" and Runtime.localWorkshopLease
                and Runtime.localWorkshopLease.resourceId=="warehouse" then Runtime.releaseLocalWorkshop("cancelled") end
        else
            local command=Runtime.RuntimeDependencies.WarehouseAuthority.command({state=Runtime.state,world=Runtime.World,save=Runtime.saveCurrent})
            local code
            accepted,code,message=command.perform({},Runtime.warehousePlayer(),{warehouseIntent=intent})
        end
        Runtime.state.message=message or (accepted and "Warehouse action completed." or "Warehouse action refused.")
        return accepted,Runtime.state.message
    end

    Runtime.warehouseControls=Runtime.RuntimeDependencies.WarehouseControls.new({state=Runtime.state,world=Runtime.World,player=Runtime.warehousePlayer,command=Runtime.sendWarehouseIntent})
end

return Component
