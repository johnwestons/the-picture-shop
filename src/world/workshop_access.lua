-- World presentation and workshop access validation.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.World.draw(assets, characterAssets, state, mouseX, mouseY, remotePlayers)
        return Runtime.WorldRenderer.draw(Runtime.World, assets, characterAssets, state, mouseX, mouseY, remotePlayers)
    end

    function Runtime.World.prompt()
        return Runtime.Interaction.prompt(Runtime.World.selectedInteraction)
    end

    function Runtime.World.getInteraction()
        return Runtime.World.selectedInteraction
    end

    function Runtime.World.interactionForPlayer(player)
        return Runtime.selectInteractionFor(player)
    end

    Runtime.WORKSHOP_RESOURCES = {
        customer = "reception_customer",
        vendor = "vendor",
        computer = "office_computer",
        workPhone = "work_phone",
        cutter = "cutter",
        skidWrapper = "skid_wrapper",
        windmill = "windmill",
        palletJack = "pallet_jack",
    }

    function Runtime.World.workshopResourceId(interactionKind, target)
        if interactionKind == "truckCargoDoor" then
            local truck = Runtime.World.truck:snapshot()
            if truck.mode == "machine_delivery" and truck.state == "parked_closed" then
                return "truck"
            end
            if truck.state == "cargo_open" then return "truck" end
            return nil
        end
        local base = Runtime.WORKSHOP_RESOURCES[interactionKind]
        if not Runtime.MachineResource.model(base) then return base end
        local machineId = target and target.machineId
        return Runtime.MachineResource.forUnit(base, machineId)
    end

    -- Workshop requests never carry client coordinates. The host resolves the
    -- physical target from its current shop state and checks the authoritative
    -- player position directly before granting an exclusive console lease.
    function Runtime.World.validateNetworkWorkshopAccess(player, state, resourceId)
        if require("src.shop_rooms").scene(player)~="warehouse" then
            return false,"wrong_scene","Return to the warehouse to use this console."
        end
        if type(player) ~= "table" or type(state) ~= "table" then
            return false, "invalid_player", "The host could not verify that worker's position."
        end
        Runtime.World._state = state
        local machineBase, machineId = Runtime.MachineResource.parse(resourceId)
        local function installedMachine(base)
            local units = Runtime.MachineFleet.installedUnits(state, Runtime.MachineResource.model(base))
            local selectedId = machineId or (player.id == 1 and state._localWorkshopMachineId)
            if not selectedId then return units[1] end
            local item = Runtime.MachineFleet.byId(state, selectedId)
            if item and item.modelId == Runtime.MachineResource.model(base)
                and item.status == "installed" then return item end
        end
        local target, unavailableMessage
        if resourceId == "reception_customer" then
            target = Runtime.World.customer:getInteraction()
            if not target or target.customerState ~= "waiting" then
                return false, "customer_unavailable", "That customer is not waiting for a conversation."
            end
            unavailableMessage = "Move closer to the waiting customer at reception."
        elseif resourceId == "vendor" then
            target = Runtime.World.vendor:getInteraction()
            if not target or (target.customerState ~= "waiting"
                and target.customerState ~= "reviewing")
            then
                return false, "vendor_unavailable", "That salesperson is not available."
            end
            unavailableMessage = "Move closer to the supplier representative."
        elseif resourceId == "truck" then
            local truck = Runtime.World.truck:snapshot()
            local manifestReady = truck.mode == "machine_delivery"
                and truck.state == "parked_closed" or truck.state == "cargo_open"
            target = Runtime.World.truck:getInteraction()
            if not target or not manifestReady then
                return false, "truck_unavailable",
                    "Open the parked truck before reviewing its manifest."
            end
            if not Runtime.World.openTruckInventory(state) then
                return false, "manifest_unavailable",
                    "That truck no longer has an available manifest."
            end
            unavailableMessage = "Move closer to the truck cargo controls."
        elseif resourceId == "office_computer" then
            target = Runtime.Config.interactables.computer
            unavailableMessage = "Move closer to the office computer."
        elseif resourceId == "work_phone" then
            target = Runtime.Config.interactables.workPhone
            unavailableMessage = "Move closer to the wall phone."
        elseif machineBase == "cutter" then
            local selected = installedMachine("cutter")
            if not selected then
                return false, "not_installed", "The paper cutter is not installed in this shop."
            end
            if Runtime.Employees.reservation(state,selected.id) then
                return false,"employee_reserved","An employee is operating this cutter. Pause their assignment in Hiring first."
            end
            local cutter = selected.world or Runtime.CutterPlacement.ensure(state, Runtime.Config.cutterPlacement)
            if cutter.moving then
                return false, "machine_moving", "Lock the cutter onto the floor before using it."
            end
            target = { x = cutter.x, y = cutter.y, radius = Runtime.Config.cutterPlacement.interactionRadius }
            unavailableMessage = "Move closer to the cutter controls."
        elseif machineBase == "skid_wrapper" then
            local selected = installedMachine("skid_wrapper")
            if not selected then
                return false, "not_installed", "The skid wrapper is not installed in this shop."
            end
            if Runtime.Employees.reservation(state,selected.id) then
                return false,"employee_reserved","An employee is operating this wrapper. Pause their assignment in Hiring first."
            end
            local wrapper = selected.world or Runtime.WrapperPlacement.ensure(state, Runtime.Config.wrapperPlacement)
            if wrapper.moving then
                return false, "machine_moving", "Lock the skid wrapper onto the floor before using it."
            end
            target = { x = wrapper.x, y = wrapper.y, radius = Runtime.Config.wrapperPlacement.interactionRadius }
            unavailableMessage = "Move closer to the skid wrapper controls."
        elseif machineBase == "windmill" then
            local selected = installedMachine("windmill")
            if not selected then
                return false, "not_installed", "The Heidelberg Windmill is not installed in this shop."
            end
            if Runtime.Employees.reservation(state,selected.id) then
                return false,"employee_reserved","An employee is operating this press. Pause their assignment in Hiring first."
            end
            local windmill = selected.world or Runtime.WindmillPlacement.ensure(state, Runtime.Config.windmillPlacement)
            if windmill.moving then
                return false, "machine_moving", "Lock the Windmill onto the floor before using it."
            end
            target = {
                x = windmill.x,
                y = windmill.y,
                radius = Runtime.Config.windmillPlacement.interactionRadius,
            }
            unavailableMessage = "Move closer to the Windmill controls."
        elseif resourceId == "pallet_jack" then
            local jack = Runtime.PalletJack.ensure(state, Runtime.Config.palletJack)
            local cutter = Runtime.CutterPlacement.ensure(state, Runtime.Config.cutterPlacement)
            local wrapper = Runtime.WrapperPlacement.ensure(state, Runtime.Config.wrapperPlacement)
            local windmill = Runtime.WindmillPlacement.ensure(state, Runtime.Config.windmillPlacement)
            if cutter.moving or wrapper.moving or windmill.moving then
                local playerId = tonumber(player.id)
                if not jack.operating or jack.operatorPlayerId ~= playerId then
                    return false, "equipment_moving",
                        "Only the worker relocating this machine may use the pallet jack."
                end
            end
            target = { x = jack.x, y = jack.y, radius = Runtime.Config.palletJack.interactionRadius }
            unavailableMessage = "Move closer to the pallet jack handle."
        else
            return false, "not_allowed", "That workshop control is not available to network workers."
        end
        local dx = (tonumber(player.x) or 0) - target.x
        local dy = (tonumber(player.y) or 0) - target.y
        local radius = math.max(0, tonumber(target.radius) or 0) + 10
        if dx * dx + dy * dy > radius * radius then
            return false, "out_of_range", unavailableMessage
        end
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.01 then
            player.intentX, player.intentY = -dx / length, -dy / length
            if math.abs(dx) > 0.01 then player.facing = dx > 0 and -1 or 1 end
        end
        return true, "available", "Workshop control is in range."
    end
end

return Component
