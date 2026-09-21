-- Gate for the authenticated Direct Play candidate.
-- The native provider remains marked as an engineering candidate, but the
-- game exposes every multiplayer option automatically when that verified
-- provider is available. No launch flag or console prompt is required.
local Gate = {}

function Gate.mode(provider)
    if type(provider) ~= "table" then return nil end
    if provider.productionReady == true then return "production" end
    if provider.engineeringOnly == true and provider.engineeringReady == true
    then
        return "engineering"
    end
    return nil
end

function Gate.enabled(provider)
    return Gate.mode(provider) ~= nil
end

function Gate.provider(provider)
    local mode = Gate.mode(provider)
    if not mode then return nil end
    if mode == "production" then return provider, mode end
    local proxy = { productionReady = true, engineeringOnly = true,
        engineeringReady = true, directTestOnly = true }
    return setmetatable(proxy, { __index = provider }), mode
end

return Gate
