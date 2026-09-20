local MachineFleet = require("src.machine_fleet")
local Procurement = require("src.procurement")

local VendorAuthority = {}

local function exactArguments(arguments, required)
    if type(arguments) ~= "table" then return false end
    local allowed = {}
    for _, name in ipairs(required or {}) do allowed[name] = true end
    for key in pairs(arguments) do
        if type(key) ~= "string" or not allowed[key] then return false end
    end
    for _, name in ipairs(required or {}) do
        if arguments[name] == nil then return false end
    end
    return true
end

local function itemIndex(arguments)
    local value = type(arguments) == "table" and arguments.itemIndex
    if not exactArguments(arguments, { "itemIndex" })
        or type(value) ~= "number" or value ~= math.floor(value)
        or value < 1 or value > 16
    then
        return nil, "invalid_item", "Choose a valid item from the live vendor catalog."
    end
    return { itemIndex = value }
end

local function noArguments(arguments)
    if not exactArguments(arguments, {}) then
        return nil, "invalid_arguments", "That vendor action takes no additional data."
    end
    return {}
end

function VendorAuthority.view(state)
    local categoryIndex = math.max(1, math.min(#Procurement.categories,
        math.floor(tonumber(state.vendorCategory) or 1)))
    local category = Procurement.category(categoryIndex)
    local rows = {}
    if category.kind == "machines" then
        for index, offer in ipairs(MachineFleet.offers("dealer")) do
            rows[#rows + 1] = {
                itemIndex = index,
                name = tostring(offer.name),
                price = math.max(0, math.floor(tonumber(offer.price) or 0)),
                available = true,
                detail = tostring(offer.conditionStatus or "used") .. " used dealer unit",
            }
        end
    else
        for index, item in ipairs(category.items) do
            local quantity = math.max(0, math.floor(tonumber(item.quantity) or 0))
            local unit = tostring(item.unit or "units")
            rows[#rows + 1] = {
                itemIndex = index,
                name = tostring(item.name),
                price = math.max(0, math.floor(tonumber(item.price) or 0)),
                available = item.available ~= false,
                detail = item.available == false
                    and tostring(item.unavailableReason or "This product is unavailable.")
                    or string.format("%d %s · dock delivery", quantity, unit),
            }
        end
    end
    return {
        categoryIndex = categoryIndex,
        categoryName = tostring(category.name),
        salesman = tostring(category.salesman),
        kind = category.kind == "machines" and "machines" or "products",
        cash = math.max(0, math.floor(tonumber(state.money) or 0)),
        items = rows,
    }
end

function VendorAuthority.resource(options)
    assert(type(options) == "table", "vendor authority options are required")
    local state = assert(options.state, "vendor authority state is required")
    local world = assert(options.world, "vendor authority world is required")
    local save = type(options.save) == "function" and options.save or function() end

    local function access(player)
        return world.validateNetworkWorkshopAccess(player, state, "vendor")
    end

    local function purchase(player, arguments, machines)
        local allowed, code, message = access(player)
        if not allowed then return false, code, message, VendorAuthority.view(state) end
        local category = Procurement.category(state.vendorCategory)
        if machines ~= (category.kind == "machines") then
            return false, "catalog_changed",
                "The live vendor catalog changed; review it before purchasing.",
                VendorAuthority.view(state)
        end
        local accepted, result
        if machines then
            accepted, result = MachineFleet.buy(state, "dealer", arguments.itemIndex)
        else
            accepted, result = Procurement.buy(state, state.vendorCategory, arguments.itemIndex)
        end
        if not accepted then
            return false, "purchase_blocked", tostring(result), VendorAuthority.view(state)
        end
        save()
        local purchaseMessage = machines
            and string.format("Purchased used %s. Unit %s is now %s.",
                tostring(result.name), tostring(result.id), tostring(result.status))
            or string.format("Purchased %s. %s is awaiting truck delivery.",
                tostring(result.productName), tostring(result.id))
        return true, machines and "machine_purchased" or "stock_purchased",
            purchaseMessage, VendorAuthority.view(state)
    end

    return {
        canAcquire = function(player)
            local allowed, code, message = access(player)
            if not allowed then return false, code, message end
            if not world.vendor or world.vendor.state ~= "waiting" then
                return false, "vendor_unavailable", "That salesperson is not waiting for a conversation."
            end
            return true
        end,
        onAcquire = function(_, player)
            if player.id == 1 then
                return true, "acquired", "Vendor reserved for the host player."
            end
            if not world.vendor:beginReview() then
                return false, "vendor_unavailable", "That salesperson is no longer waiting."
            end
            return true, "acquired", "Vendor catalog connected.",
                VendorAuthority.view(state), { remote = true }
        end,
        onRelease = function(lease)
            if lease and lease.private and lease.private.remote
                and world.vendor and world.vendor.state == "reviewing"
            then
                world.vendor:cancelReview()
            end
            return true
        end,
        commands = {
            purchase_stock = {
                normalize = itemIndex,
                perform = function(_, player, arguments)
                    return purchase(player, arguments, false)
                end,
            },
            purchase_machine = {
                normalize = itemIndex,
                perform = function(_, player, arguments)
                    return purchase(player, arguments, true)
                end,
            },
            dismiss = {
                normalize = noArguments,
                perform = function(_, player)
                    local allowed, code, message = access(player)
                    if not allowed then
                        return false, code, message, VendorAuthority.view(state)
                    end
                    if not world.resolveVendor(state, "declined") then
                        return false, "vendor_unavailable",
                            "That salesperson is no longer reviewing the catalog.",
                            VendorAuthority.view(state)
                    end
                    save()
                    return true, "dismissed", "The salesperson is heading out.",
                        VendorAuthority.view(state)
                end,
            },
        },
    }
end

return VendorAuthority
