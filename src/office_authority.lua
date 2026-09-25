local Intent = require("src.office_intent")
local Projection = require("src.screens.gui_projection")
local Computer = require("src.screens.computer_screen")
local JobService = require("src.job_service")
local MachineFleet = require("src.machine_fleet")
local Procurement = require("src.procurement")
local Calendar = require("src.business_calendar")
local Upgrades = require("src.warehouse_upgrades")
local Credit = require("src.credit")

local Office = {}
local function merge(target, source)
    for key in pairs(target) do if source[key] == nil then target[key] = nil end end
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then merge(target[key], value)
        else target[key] = value end
    end
end
function Office.command(options)
    return {
        normalize = function(args)
            if type(args) ~= "table" then return nil, "invalid_arguments" end
            for key in pairs(args) do if key ~= "officeIntent" then return nil, "invalid_arguments" end end
            local intent, errorMessage = Intent.normalize(args.officeIntent)
            if not intent then return nil, "invalid_office_action", errorMessage end
            return { officeIntent = intent }
        end,
        perform = function(_, player, args)
            local state = options.state
            local allowed, code, message = options.world.validateNetworkWorkshopAccess(player, state, "office_computer")
            if not allowed then return false, code, message, {} end
            local intent, errorMessage = Intent.normalize(args and args.officeIntent)
            if not intent then return false, "invalid_office_action", errorMessage, {} end
            local warehousePurchase = intent.kind == "buy_upgrade" or intent.kind == "buy_forklift"
            if warehousePurchase then
                local enabled = type(options.warehouseEnabled) == "function" and options.warehouseEnabled(state)
                    or options.warehouseEnabled == true
                if enabled ~= true then return false, "warehouse_disabled", "Warehouse upgrades are not enabled in this build.", {} end
                if options.warehouseFirstStorageOnly == true and intent.kind == "buy_upgrade"
                    and (intent.bayId ~= "front_left" or intent.optionId ~= "storage") then
                    return false, "warehouse_not_ready", "Only the left storage expansion is ready in this build.", {}
                end
                if intent.kind == "buy_upgrade" and intent.optionId == "storage"
                    and not (state.warehouse and state.warehouse.forkliftOwned)
                    and intent.confirmUpperRows ~= true then
                    return false, "forklift_warning_required", "Confirm that the upper five shelves require a forklift.", {}
                end
            end
            local staged = Projection.copy(state)
            local ok, result, domainCode
            if intent.kind == "estimate" then ok, result = JobService.submitEmailQuote(staged, intent.id, intent.amount, os.time())
            elseif intent.kind == "decline" then ok, result = JobService.respondToEmail(staged, intent.id, "declined", os.time())
            elseif intent.kind == "promotion" then
                local job
                for _, candidate in ipairs(staged.jobs.completed or {}) do if candidate.id == intent.id then job = candidate end end
                if job then ok, result = JobService.sendPromotion(staged, job, intent.text) end
            elseif intent.kind == "archive" then ok, result = JobService.dismissInboxNotice(staged, intent.id)
            elseif intent.kind == "archive_service" then ok, result = MachineFleet.dismissServiceNotice(staged, intent.id)
            elseif intent.kind == "sell" then ok, result = MachineFleet.sell(staged, intent.id, "online")
            elseif intent.kind == "pay_bills" then ok, result = Calendar.pay(staged)
            elseif intent.kind == "finance_machine" then
                ok, result, domainCode = Credit.financeMachine(staged, intent.offerIndex,
                    intent.requestId, intent.channel)
            elseif intent.kind == "pay_machine_loan" then ok, result = Credit.payLoan(staged, intent.loanId)
            elseif intent.kind == "buy_upgrade" then
                ok, result, domainCode = Upgrades.purchase(staged, intent.bayId, intent.optionId, intent.requestId)
            elseif intent.kind == "buy_forklift" then
                ok, result, domainCode = Upgrades.purchaseForklift(staged, intent.requestId)
            elseif intent.kind == "checkout" then
                local screen = Computer.new()
                local entries = {}
                for _, row in ipairs(intent.items) do
                    local entry = Projection.copy(row)
                    if row.kind == "supply" then
                        local category = Procurement.categories[row.categoryIndex]
                        local product = category and category.items[row.itemIndex]
                        if not product or not product.retailPrice then return false, "product_changed", "The product is no longer listed.", {} end
                        entry.price, entry.name = product.retailPrice, product.retailName
                    else
                        local offer = MachineFleet.offers("online")[row.offerIndex]
                        if not offer then return false, "product_changed", "The machine is no longer listed.", {} end
                        entry.price, entry.name, entry.modelId = offer.price, offer.name, offer.modelId
                    end
                    entries[#entries + 1] = entry
                end
                ok, result = screen.checkout(staged, entries)
            end
            if not ok then return false, "office_blocked", type(result) == "string" and result or "That office action is no longer available.", {} end
            if warehousePurchase and domainCode == "replayed" then
                return true, "replayed", "This purchase was already confirmed; no second charge was made.", {}
            end
            if intent.kind == "finance_machine" and domainCode == "replayed" then
                return true, "replayed", "This financing agreement was already signed; no second loan was created.", {}
            end
            merge(state, staged)
            options.save()
            return true, "completed", "Office action completed and saved by the host.", {}
        end,
    }
end
return Office
