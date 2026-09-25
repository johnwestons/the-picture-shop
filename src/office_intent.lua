local Codec = require("src.net.codec")
local Intent = {}
local fields = {
    estimate = { id = "token", amount = "amount" }, decline = { id = "token" },
    promotion = { id = "token", text = "text" }, archive = { id = "token" },
    archive_service = { id = "token" }, sell = { id = "token" },
    pay_bills = {}, checkout = { items = "cart" },
    finance_machine = { offerIndex = "machine_offer", requestId = "token", channel = "machine_channel" },
    pay_machine_loan = { loanId = "token" },
    buy_upgrade = { bayId = "bay", optionId = "upgrade", requestId = "token", confirmUpperRows = "optional_boolean" },
    buy_forklift = { requestId = "token" },
}
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
function Intent.normalize(value)
    if type(value) ~= "table" or not fields[value.kind] then return nil, "Unknown office action." end
    local schema, result = fields[value.kind], { kind = value.kind }
    for key in pairs(value) do if key ~= "kind" and not schema[key] then return nil, "Unexpected office data." end end
    for key, rule in pairs(schema) do
        local item = value[key]
        if rule == "bay" then
            if item ~= "front_left" and item ~= "front_right" then return nil, "Choose a warehouse bay." end
        elseif rule == "upgrade" then
            if item ~= "floor" and item ~= "storage" and item ~= "breakroom" then return nil, "Choose a warehouse upgrade." end
        elseif rule == "optional_boolean" then
            if item ~= nil and type(item) ~= "boolean" then return nil, "Invalid shelf warning confirmation." end
        elseif rule == "token" then
            if type(item) ~= "string" or #item < 1 or #item > 64 or not item:match("^[%w_.%-]+$") then return nil, "Invalid record ID." end
        elseif rule == "amount" then
            if not integer(item, 1, 10000000) then return nil, "Invalid estimate amount." end
        elseif rule == "machine_offer" then
            if not integer(item, 1, 16) then return nil, "Choose a listed machine." end
        elseif rule == "machine_channel" then
            if item == nil then item = "online" end
            if item ~= "online" and item ~= "dealer" then return nil, "Choose a listed machine channel." end
        elseif rule == "text" then
            if type(item) ~= "string" or #item > 600 or item:find("[%z\1-\8\11\12\14-\31]") then return nil, "Invalid message." end
        elseif rule == "cart" then
            if type(item) ~= "table" or #item < 1 or #item > 6 then return nil, "Use a cart of 1–6 different products." end
            local rows, count = {}, 0
            for index, row in pairs(item) do
                if not integer(index, 1, #item) or type(row) ~= "table" then return nil, "Invalid cart row." end
                local allowed = row.kind == "supply" and { kind=true, quantity=true, categoryIndex=true, itemIndex=true }
                    or row.kind == "machine" and { kind=true, quantity=true, offerIndex=true }
                if not allowed or not integer(row.quantity, 1, 10) then return nil, "Invalid product quantity." end
                local copy = {}
                for field, data in pairs(row) do
                    if not allowed[field] then return nil, "Client prices are not accepted." end
                    copy[field] = data
                end
                if row.kind == "supply" and (not integer(row.categoryIndex, 1, 5) or not integer(row.itemIndex, 1, 16))
                    or row.kind == "machine" and not integer(row.offerIndex, 1, 16) then return nil, "Invalid product choice." end
                count = count + row.quantity
                rows[index] = copy
            end
            if count > 20 then return nil, "Use at most 20 products per checkout." end
            item = Codec.array(rows)
        end
        result[key] = item
    end
    return result
end
return Intent
