local Intent = require("src.warehouse_intent")
local Warehouse = {}

-- Used by both local controls and the authenticated workshop lease. The world
-- owns physical range/alignment, collision and the atomic domain transfers.
function Warehouse.command(options)
    return {
        normalize = function(args)
            if type(args) ~= "table" then return nil, "invalid_arguments" end
            for key in pairs(args) do
                if key ~= "warehouseIntent" then return nil, "invalid_arguments" end
            end
            local intent, message = Intent.normalize(args.warehouseIntent)
            if not intent then return nil, "invalid_warehouse_action", message end
            return { warehouseIntent = intent }
        end,
        perform = function(lease, player, args)
            if type(player) ~= "table" or type(player.id) ~= "number"
                or player.id < 1 or player.id > 4 or player.id ~= math.floor(player.id)
            then return false, "invalid_player", "An authenticated worker is required.", {} end
            local intent, message = Intent.normalize(args and args.warehouseIntent)
            if not intent then return false, "invalid_warehouse_action", message, {} end
            if lease and lease.resourceId == "pallet_jack" and (intent.vehicle ~= "pallet_jack"
                or (intent.kind ~= "store" and intent.kind ~= "retrieve")) then
                return false, "wrong_vehicle_lease", "Pallet-jack controls can only transfer their own load at a rack.", {}
            end
            local allowed, code, accessMessage = options.world.warehouseAccess(player, options.state, intent)
            if not allowed then return false, code or "out_of_range", accessMessage or "Move closer to the warehouse equipment.", {} end
            local accepted, resultCode, resultMessage = options.world.warehouseCommand(player, options.state, intent)
            if not accepted then return false, resultCode or "warehouse_blocked", resultMessage or "That warehouse action is not available.", {} end
            if resultCode ~= "replayed" and options.save then options.save() end
            return true, resultCode or "completed", resultMessage or "Warehouse action completed.", {}
        end,
    }
end
return Warehouse
