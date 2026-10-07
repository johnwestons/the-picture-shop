-- Resource-specific workshop view dispatch.
-- Runtime is private to this module; shared state remains live across components.
local Component = {}

function Component.install(Runtime)
    function Runtime.normalizeWorkshopView(value, resourceId, label)
        resourceId = Runtime.WORKSHOP_RESOURCES[resourceId] and resourceId
            or Runtime.MachineResource.parse(resourceId)
        if resourceId == "reception_customer" then
            return Runtime.normalizeReceptionWorkshopView(value, label)
        elseif resourceId == "vendor" then
            local valid, shapeError = Runtime.shape(value, label, {
                "categoryIndex", "categoryName", "salesman", "kind", "cash", "items",
            })
            if not valid then return nil, shapeError end
            local normalized, fieldError = {}
            normalized.categoryIndex, fieldError = Runtime.integerInRange(
                value.categoryIndex, 1, 5, label .. ".categoryIndex")
            if not normalized.categoryIndex then return nil, fieldError end
            for _, field in ipairs({ "categoryName", "salesman" }) do
                normalized[field], fieldError = Runtime.printableString(
                    value[field], 1, 64, label .. "." .. field)
                if not normalized[field] then return nil, fieldError end
            end
            if value.kind ~= "products" and value.kind ~= "machines" then
                return nil, label .. ".kind is invalid"
            end
            normalized.kind = value.kind
            normalized.cash, fieldError = Runtime.integerInRange(value.cash, 0, Runtime.UINT32_MAX,
                label .. ".cash")
            if normalized.cash == nil then return nil, fieldError end
            if not Runtime.Codec.isArray(value.items) or #value.items > 5 then
                return nil, label .. ".items must be an array of at most 5 rows"
            end
            local rows = {}
            for index, row in ipairs(value.items) do
                local rowLabel = label .. ".items[" .. index .. "]"
                local rowValid, rowError = Runtime.shape(row, rowLabel,
                    { "itemIndex", "name", "price", "available", "detail" })
                if not rowValid then return nil, rowError end
                local projected = {}
                projected.itemIndex, fieldError = Runtime.integerInRange(
                    row.itemIndex, 1, 16, rowLabel .. ".itemIndex")
                if not projected.itemIndex or projected.itemIndex ~= index then
                    return nil, rowLabel .. ".itemIndex must match its row"
                end
                for _, field in ipairs({ "name", "detail" }) do
                    projected[field], fieldError = Runtime.printableString(
                        row[field], 1, 96, rowLabel .. "." .. field)
                    if not projected[field] then return nil, fieldError end
                end
                projected.price, fieldError = Runtime.integerInRange(
                    row.price, 0, Runtime.UINT32_MAX, rowLabel .. ".price")
                if projected.price == nil then return nil, fieldError end
                if type(row.available) ~= "boolean" then
                    return nil, rowLabel .. ".available must be boolean"
                end
                projected.available = row.available
                rows[#rows + 1] = projected
            end
            normalized.items = Runtime.Codec.array(rows)
            return normalized
        elseif resourceId == "truck" then
            local valid, shapeError = Runtime.shape(value, label, {
                "mode", "state", "manifestId", "title", "page", "pageCount",
                "remaining", "canClose", "items",
            })
            if not valid then return nil, shapeError end
            if not Runtime.WORKSHOP_TRUCK_MODES[value.mode] then
                return nil, label .. ".mode is invalid"
            end
            if not Runtime.WORKSHOP_TRUCK_STATES[value.state] then
                return nil, label .. ".state is invalid"
            end
            local normalized, fieldError = {
                mode = value.mode,
                state = value.state,
            }
            normalized.manifestId, fieldError = Runtime.token(
                value.manifestId, Runtime.MAX_TOKEN_BYTES, label .. ".manifestId")
            if not normalized.manifestId then return nil, fieldError end
            normalized.title, fieldError = Runtime.printableString(
                value.title, 1, 96, label .. ".title")
            if not normalized.title then return nil, fieldError end
            normalized.page, fieldError = Runtime.integerInRange(value.page, 1, 64, label .. ".page")
            if not normalized.page then return nil, fieldError end
            normalized.pageCount, fieldError = Runtime.integerInRange(
                value.pageCount, 1, 64, label .. ".pageCount")
            if not normalized.pageCount or normalized.page > normalized.pageCount then
                return nil, label .. ".page must not exceed pageCount"
            end
            normalized.remaining, fieldError = Runtime.integerInRange(
                value.remaining, 0, 10000, label .. ".remaining")
            if normalized.remaining == nil then return nil, fieldError end
            if type(value.canClose) ~= "boolean" then
                return nil, label .. ".canClose must be boolean"
            end
            normalized.canClose = value.canClose
            if value.canClose ~= (value.remaining == 0
                and (value.mode == "machine_delivery" and value.state == "parked_closed"
                    or value.mode ~= "machine_delivery" and value.state == "cargo_open"))
            then
                return nil, label .. ".canClose is inconsistent"
            end
            if not Runtime.Codec.isArray(value.items) or #value.items > 3 then
                return nil, label .. ".items must be an array of at most 3 rows"
            end
            local rows = {}
            for index, row in ipairs(value.items) do
                local rowLabel = label .. ".items[" .. index .. "]"
                local rowValid, rowError = Runtime.shape(row, rowLabel,
                    { "itemIndex", "label", "detail", "available" })
                if not rowValid then return nil, rowError end
                local projected = {}
                projected.itemIndex, fieldError = Runtime.integerInRange(
                    row.itemIndex, 1, 3, rowLabel .. ".itemIndex")
                if not projected.itemIndex or projected.itemIndex ~= index then
                    return nil, rowLabel .. ".itemIndex must match its row"
                end
                for _, field in ipairs({ "label", "detail" }) do
                    projected[field], fieldError = Runtime.printableString(
                        row[field], 1, 96, rowLabel .. "." .. field)
                    if not projected[field] then return nil, fieldError end
                end
                if type(row.available) ~= "boolean" then
                    return nil, rowLabel .. ".available must be boolean"
                end
                projected.available = row.available
                rows[#rows + 1] = projected
            end
            normalized.items = Runtime.Codec.array(rows)
            return normalized
        elseif resourceId == "office_computer" or resourceId == "work_phone" or resourceId == "warehouse" then
            local valid, shapeError = Runtime.shape(value, label, {})
            if not valid then return nil, shapeError end
            return {}
        elseif resourceId == "skid_wrapper" then
            return Runtime.normalizeWrapperWorkshopView(value, label)
        elseif resourceId == "pallet_jack" then
            local valid, shapeError = Runtime.shape(value, label, {})
            if not valid then return nil, shapeError end
            return {}
        elseif resourceId == "cutter" then
            return Runtime.normalizeCutterWorkshopView(value, label)
        elseif resourceId == "windmill" then
            return Runtime.normalizeWindmillWorkshopView(value, label)
        end
        return nil, label .. " has no resource validator"
    end
end

return Component
