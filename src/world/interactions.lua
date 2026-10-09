-- Interaction targets and player interaction selection.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.interactables(player)
        player = player or Runtime.World.player
        local Rooms=require("src.shop_rooms")
        local targets = Rooms.targets(player, Runtime.World._state)
        local function addTarget(kind, target, key)
            Runtime.MultiplayerCapabilities.requireInteraction(kind)
            if target then
                target.kind = kind
                targets[key or kind] = target
            end
        end
        local jack=Runtime.World._state and Runtime.PalletJack.ensure(
            Runtime.World._state,Runtime.Config.palletJack)
        if jack and jack.sceneId==Rooms.scene(player) then
            addTarget("palletJack",Runtime.PalletJack.interaction(
                player,Runtime.World._state,Runtime.Config.palletJack))
        end
        if Rooms.scene(player)~="warehouse" then return targets end
        addTarget("computer", Runtime.Config.interactables.computer)
        addTarget("shopClock", Runtime.Config.interactables.shopClock)
        addTarget("jukebox", Runtime.Config.interactables.jukebox)
        local phoneTarget = {
            x = Runtime.Config.interactables.workPhone.x,
            y = Runtime.Config.interactables.workPhone.y,
            radius = Runtime.Config.interactables.workPhone.radius,
            hoverX = Runtime.Config.interactables.workPhone.hoverX,
            hoverY = Runtime.Config.interactables.workPhone.hoverY,
            hoverRadius = Runtime.Config.interactables.workPhone.hoverRadius,
            prompt = Runtime.World._state and Runtime.World._state.workPhone
                and Runtime.World._state.workPhone.incoming
                and "E: answer ringing wall phone" or "E: use wall phone",
        }
        addTarget("workPhone", phoneTarget)
        local customerInteraction = Runtime.World.customer:getInteraction()
        addTarget("customer", customerInteraction)
        if Runtime.World._state then
            for _,a in ipairs(Runtime.Employees.ensure(Runtime.World._state).applications) do
                if a.status=="visiting" and a.actor.visible and a.actor.phase=="waiting" then
                    local employeeOptions=Runtime.World._employeeOptions
                    local networkClient=employeeOptions and employeeOptions.isNetworkClient
                        and employeeOptions.isNetworkClient()
                    addTarget("applicant",{x=a.actor.x,y=a.actor.y,radius=68,applicationId=a.id,
                        prompt=networkClient
                            and "The shop owner handles employment applications"
                            or "E: request resume   X: dismiss applicant"})
                end
            end
        end
        local vendorInteraction = Runtime.World.vendor:getInteraction()
        if vendorInteraction then
            vendorInteraction.prompt = "E: talk to the " .. Runtime.Procurement.category(Runtime.World._state and Runtime.World._state.vendorCategory).name:lower() .. " salesman"
            addTarget("vendor", vendorInteraction)
        end
        addTarget("loadingBayDoor", Runtime.World.bayDoor:getInteraction())
        local truckInteraction = Runtime.World.truck:getInteraction()
        addTarget("truckCargoDoor", truckInteraction)
        if Runtime.World._state then
            local networkMachineView = Runtime.World._state._networkMachinePoses ~= nil
            local nearestPallet
            local nearestDistance
            for _, item in ipairs(Runtime.PalletLogistics.physicalPallets(Runtime.World._state)) do
                if item.pallet.world and (item.pallet.world.sceneId or "warehouse")=="warehouse" then
                    local distance = (player.x - item.x) ^ 2 + (player.y - item.y) ^ 2
                    local radius = Runtime.Config.palletLogistics.interactionRadius or 92
                    if distance <= radius * radius and (not nearestDistance or distance < nearestDistance) then
                        nearestPallet, nearestDistance = item, distance
                    end
                end
            end
            if nearestPallet then
                addTarget("palletWorkOrder", {
                    x = nearestPallet.x, y = nearestPallet.y,
                    radius = Runtime.Config.palletLogistics.interactionRadius or 92,
                    prompt = "E: inspect work order",
                    item = nearestPallet,
                })
            end
            jack = Runtime.PalletJack.ensure(Runtime.World._state, Runtime.Config.palletJack)
            local playerId = type(player.id) == "number" and player.id
                or (player == Runtime.World.player and 1 or nil)
            local jackReady = jack.operating and not jack.carriedPalletId
                and jack.operatorPlayerId == playerId
            local cutters = Runtime.MachineFleet.installedUnits(Runtime.World._state, "polar_115")
            if cutters[1] and not cutters[1].world
                and not (networkMachineView and Runtime.World._state.cutter.moving)
            then
                local target = Runtime.CutterPlacement.interaction(player, Runtime.World._state,
                    Runtime.Config.cutterPlacement, jackReady)
                target.machineId = cutters[1].id
                addTarget("cutter", target)
            end
            for index = 1, #cutters do
                local item = cutters[index]
                if item.world then addTarget("cutter", {
                    x = item.world.x, y = item.world.y,
                    radius = Runtime.Config.cutterPlacement.interactionRadius,
                    prompt = "E: use " .. item.name .. " (" .. item.id .. ")"
                        .. (jackReady and "  |  M: relocate with pallet jack" or ""),
                    machineId = item.id,
                }, "cutter:" .. item.id) end
            end
            local wrappers = Runtime.MachineFleet.installedUnits(Runtime.World._state, "skid_wrapper")
            if wrappers[1] and not wrappers[1].world
                and not (networkMachineView and Runtime.World._state.wrapper.moving)
            then
                local target = Runtime.WrapperPlacement.interaction(player, Runtime.World._state,
                    Runtime.Config.wrapperPlacement, jackReady)
                target.machineId = wrappers[1].id
                addTarget("skidWrapper", target)
            end
            for index = 1, #wrappers do
                local item = wrappers[index]
                if item.world then addTarget("skidWrapper", {
                    x = item.world.x, y = item.world.y,
                    radius = Runtime.Config.wrapperPlacement.interactionRadius,
                    prompt = "E: use skid wrapper (" .. item.id .. ")"
                        .. (jackReady and "  |  M: relocate with pallet jack" or ""),
                    machineId = item.id,
                }, "wrapper:" .. item.id) end
            end
            local windmills = Runtime.MachineFleet.installedUnits(Runtime.World._state, "heidelberg_10x15")
            if windmills[1] and not windmills[1].world
                and not (networkMachineView and Runtime.World._state.windmill.moving)
            then
                local target = Runtime.WindmillPlacement.interaction(player, Runtime.World._state,
                    Runtime.Config.windmillPlacement, jackReady)
                target.machineId = windmills[1].id
                addTarget("windmill", target)
            end
            for index = 1, #windmills do
                local item = windmills[index]
                if item.world then addTarget("windmill", {
                    x = item.world.x, y = item.world.y,
                    radius = Runtime.Config.windmillPlacement.interactionRadius,
                    prompt = "E: operate Windmill (" .. item.id .. ")"
                        .. (jackReady and "  |  M: relocate with pallet jack" or ""),
                    machineId = item.id,
                }, "windmill:" .. item.id) end
            end
            local lift = Runtime.Forklift.ensure(Runtime.World._state, Runtime.Config.forklift)
            if lift.owned then
                addTarget("forklift", {x=lift.x,y=lift.y,radius=(Runtime.Config.forklift and Runtime.Config.forklift.interactionRadius) or 76,
                    prompt=lift.operating and lift.operatorPlayerId==playerId
                        and "E: forklift controls  |  F: park" or "E: operate forklift"})
            end
            local rackId,nearbyShelf = Runtime.World.warehouseNearRack(player, Runtime.World._state)
            if rackId then
                local approach = nearbyShelf or Runtime.WarehouseLayout.rackApproach(rackId)
                local shelf=Runtime.Config.warehouse.roomScenes and Runtime.WarehouseLayout.rackPoint(rackId,1,3)
                addTarget("palletRack", {x=approach.x,y=approach.y,radius=130,rackId=rackId,
                    hoverX=shelf and shelf.x,hoverY=shelf and shelf.y,hoverRadius=shelf and 160 or nil,
                    prompt="E: view pallet shelves"})
            end
            for _,bayId in ipairs(Runtime.WarehouseLayout.BAY_IDS) do
                local bay=Runtime.WarehouseLayout.bay(bayId)
                local room=Runtime.WarehouseLayout.bayState(Runtime.World._state,bayId)
                if not Runtime.Config.warehouse.roomScenes and room and room.status=="complete" and room.optionId=="breakroom" then
                    addTarget("breakroom",{x=bay.restPoint.x,y=bay.restPoint.y,radius=66,bayId=bayId,
                        prompt=player.resting and "E: get back to work" or "E: take a break"})
                end
            end
            if jackReady and Runtime.activeMachineKind(Runtime.World._state) then
                targets.palletJack.prompt = "E: place machine  |  Q: TURN"
            elseif jackReady and not targets.palletJack.candidatePalletId then
                local candidate = Runtime.World.nearbyMachineMove(Runtime.World._state)
                if candidate then
                    targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE " .. candidate.target.machineId
                end
                local cutter = Runtime.CutterPlacement.ensure(Runtime.World._state, Runtime.Config.cutterPlacement)
                local wrapper = Runtime.WrapperPlacement.ensure(Runtime.World._state, Runtime.Config.wrapperPlacement)
                local windmill = Runtime.WindmillPlacement.ensure(Runtime.World._state, Runtime.Config.windmillPlacement)
                local cutterNear = (jack.x - cutter.x) ^ 2 + (jack.y - cutter.y) ^ 2
                    <= Runtime.Config.cutterPlacement.interactionRadius ^ 2
                local wrapperNear = (jack.x - wrapper.x) ^ 2 + (jack.y - wrapper.y) ^ 2
                    <= Runtime.Config.wrapperPlacement.interactionRadius ^ 2
                local windmillNear = (jack.x - windmill.x) ^ 2 + (jack.y - windmill.y) ^ 2
                    <= Runtime.Config.windmillPlacement.interactionRadius ^ 2
                if not candidate and cutterNear then
                    targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE CUTTER"
                elseif not candidate and wrapperNear then
                    targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE WRAPPER"
                elseif not candidate and windmillNear then
                    targets.palletJack.prompt = "F: park pallet jack  |  M: RELOCATE WINDMILL"
                end
            end
        end
        return targets
    end

    function Runtime.selectInteractionFor(player, previous, cursorX, cursorY)
        local ordinary = Runtime.Interaction.select(player, Runtime.interactables(player), cursorX, cursorY, previous, {
            stickiness = Runtime.Config.player.interactionStickiness,
            facingWeight = Runtime.Config.player.interactionFacingWeight,
        })
        local pickup = Runtime.World.palletPickupSnapshot(Runtime.World._state, cursorX, cursorY, player)
        return require("src.pallet_pickup").interaction(pickup, player, ordinary)
    end

    function Runtime.selectNetworkInteractionFor(player, previous, cursorX, cursorY)
        if require("src.shop_rooms").scene(player)~="warehouse" then
            return Runtime.selectInteractionFor(player,previous,cursorX,cursorY)
        end
        local selected = Runtime.selectInteractionFor(player, previous, cursorX, cursorY)
        if selected and selected.target and selected.target.pickup then return selected end
        local previousDoor = previous and previous.kind == "loadingBayDoor" and previous or nil
        local door = Runtime.Interaction.select(player, {
            loadingBayDoor = Runtime.World.bayDoor:getInteraction(),
        }, cursorX, cursorY, previousDoor, {
            stickiness = Runtime.Config.player.interactionStickiness,
            facingWeight = Runtime.Config.player.interactionFacingWeight,
        })
        -- The only guest-enabled target wins throughout its operating radius, even
        -- when a parked truck's larger prompt overlaps the wall switch.
        return door or selected
    end

    function Runtime.World.interactionAt(x, y, networkClient)
        local selector = networkClient and Runtime.selectNetworkInteractionFor
            or Runtime.selectInteractionFor
        Runtime.World.selectedInteraction = selector(
            Runtime.World.player, Runtime.World.selectedInteraction, x, y)
        return Runtime.World.selectedInteraction
    end
end

return Component
