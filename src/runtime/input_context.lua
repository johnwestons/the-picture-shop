-- Game input dependencies and interaction callbacks.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    Runtime.inputContext = {
        state = Runtime.state,
        assets = Runtime.Assets,
        computerScreen = Runtime.ComputerScreen,
        workPhoneScreen = Runtime.WorkPhoneScreen,
        hud = Runtime.RuntimeDependencies.Hud,
        world = Runtime.World,
        shop = Runtime.Shop,
        jobOfferScreen = Runtime.JobOfferScreen,
        workshopRemoteScreen = Runtime.WorkshopRemoteScreen,
        jobService = Runtime.JobService,
        machine = Runtime.Machine,
        wrapper = Runtime.Wrapper,
        machineScreen = Runtime.MachineScreen,
        truckInventoryScreen = Runtime.RuntimeDependencies.TruckInventoryScreen,
        vendorScreen = Runtime.VendorScreen,
        palletWorkOrderScreen = Runtime.RuntimeDependencies.PalletWorkOrderScreen,
        pressScreen = Runtime.PressScreen,
        windmill = Runtime.Windmill,
        title = Runtime.TitleScreen,
        saveCurrent = Runtime.saveCurrent,
        isNetworkClient = function() return Runtime.multiplayer:isClient() end,
        cutterControlOccupied = function()
            local target = Runtime.World.selectedInteraction and Runtime.World.selectedInteraction.target
            local resourceId = Runtime.World.workshopResourceId("cutter", target)
            return Runtime.workshopAuthority and Runtime.workshopAuthority:leaseForResource(resourceId) ~= nil
        end,
        wrapperControlOccupied = function()
            local target = Runtime.World.selectedInteraction and Runtime.World.selectedInteraction.target
            local resourceId = Runtime.World.workshopResourceId("skidWrapper", target)
            return Runtime.workshopAuthority and Runtime.workshopAuthority:leaseForResource(resourceId) ~= nil
        end,
        windmillControlOccupied = function()
            local target = Runtime.World.selectedInteraction and Runtime.World.selectedInteraction.target
            local resourceId = Runtime.World.workshopResourceId("windmill", target)
            return Runtime.workshopAuthority and Runtime.workshopAuthority:leaseForResource(resourceId) ~= nil
        end,
        palletJackControl = Runtime.handlePalletJackControl,
        networkInteraction = function(selected)
            if selected and selected.kind=="forklift" then Runtime.sendWarehouseIntent({kind="operate"}); return true end
        if selected and selected.kind=="palletRack" then
            return Runtime.warehouseControls:openRack(selected.target and selected.target.rackId)
        end
        -- Sitting is local presentation only and carries no shared state.
        if selected and selected.kind=="breakroom" then return false end
        if selected and selected.kind=="jukebox" then return false end
            if not Runtime.multiplayer:isActive() then return false end
            if not selected then
                if Runtime.multiplayer:isClient() then
                    Runtime.state.message = "Move beside a workshop control before using it."
                    return true
                end
                return false
            end
            local resourceId = Runtime.World.workshopResourceId(selected.kind, selected.target)
            if Runtime.multiplayer:isHost() and resourceId then
                Runtime.state._localWorkshopMachineId = selected.target and selected.target.machineId
                local lease = Runtime.workshopAuthority and Runtime.workshopAuthority:leaseForResource(resourceId)
                if lease and lease.ownerPlayerId ~= 1 then
                    Runtime.state._localWorkshopMachineId = nil
                    Runtime.state.message = "Another worker is using that workshop control."
                    return true
                end
                local acquired, acquireMessage = Runtime.acquireLocalWorkshop(resourceId)
                if not acquired then
                    Runtime.state._localWorkshopMachineId = nil
                    Runtime.state.message = tostring(acquireMessage or "That workshop control is unavailable.")
                    return true
                end
                if resourceId == "pallet_jack" then
                    Runtime.state.message = tostring(acquireMessage
                        or "Operating pallet jack. Drive with movement controls.")
                    return true
                end
                return false
            end
            if not Runtime.multiplayer:isClient() then return false end
            if resourceId then
                local requested, errorMessage = Runtime.multiplayer:requestWorkshopAcquire(resourceId)
                Runtime.state.message = requested
                    and "Waiting for the host device to reserve that workshop control..."
                    or tostring(errorMessage or "The workshop request could not be sent.")
                return true
            end
            if selected.kind ~= "loadingBayDoor" and selected.kind ~= "truckCargoDoor" then
                Runtime.state.message = "That shop-floor action is not worker-enabled yet."
                return true
            end
            local doorState = selected.kind == "truckCargoDoor"
                and selected.target and selected.target.truckState
                or selected.target and selected.target.doorState
            if selected.kind == "truckCargoDoor" then
                if doorState == "parked_closed" then doorState = "closed"
                elseif doorState == "cargo_open" then doorState = "open"
                else doorState = nil end
            end
            if doorState ~= "closed" and doorState ~= "open" then
                Runtime.state.message = selected.kind == "truckCargoDoor"
                    and "Wait for the truck cargo door to finish moving."
                    or "Wait for the loading-bay door to finish moving."
                return true
            end
            local desiredState = doorState == "closed" and "open" or "closed"
            local requested, errorMessage = Runtime.multiplayer:requestInteraction(
                selected.kind, desiredState)
            Runtime.state.message = requested
                and (selected.kind == "truckCargoDoor"
                    and "Waiting for the host device to verify the truck cargo door..."
                    or "Waiting for the host device to verify the loading-bay switch...")
                or tostring(errorMessage or "The interaction request could not be sent.")
            return true
        end,
        requestWorkshopCommand = function(action, arguments)
            return Runtime.multiplayer:requestWorkshopCommand(action, arguments)
        end,
        releaseWorkshopInteraction = function(reason)
            if Runtime.multiplayer:isClient() then return Runtime.multiplayer:releaseWorkshop(reason) end
            if Runtime.multiplayer:isHost() then return Runtime.releaseLocalWorkshop(reason) end
            return false
        end,
        returnToTitle = Runtime.returnToTitle,
        worldPointerCoordinates = function(x, y)
            Runtime.syncCamera()
            if Runtime.App.cameraTransformsWorld() then
                return Runtime.App.mobileCamera:screenToWorld(x, y)
            end
            return x, y
        end,
    }
end

return Component
