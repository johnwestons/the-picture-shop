-- Explicit opt-in gate for exercising the authenticated Direct Play candidate.
-- Production builds remain fail-closed: the engineering path is enabled only
-- when the operator sets PICTURE_SHOP_ENABLE_DIRECT_TEST=1 before launch.
local Gate = {}

local function enabledValue(value)
    value = tostring(value or ""):lower()
    return value == "1" or value == "true" or value == "yes"
end

function Gate.engineeringRequested(getenv)
    if type(getenv) ~= "function" then return false end
    local ok, value = pcall(getenv, "PICTURE_SHOP_ENABLE_DIRECT_TEST")
    return ok and enabledValue(value)
end

function Gate.mode(provider, getenv)
    if type(provider) ~= "table" then return nil end
    if provider.productionReady == true then return "production" end
    if provider.engineeringOnly == true and provider.engineeringReady == true
        and Gate.engineeringRequested(getenv)
    then
        return "engineering"
    end
    return nil
end

function Gate.enabled(provider, getenv)
    return Gate.mode(provider, getenv) ~= nil
end

function Gate.provider(provider, getenv)
    local mode = Gate.mode(provider, getenv)
    if not mode then return nil end
    if mode == "production" then return provider, mode end
    local proxy = { productionReady = true, engineeringOnly = true,
        engineeringReady = true, directTestOnly = true }
    return setmetatable(proxy, { __index = provider }), mode
end

return Gate
