-- Developer-only Windows LAN-host bootstrap. Normal builds do nothing unless
-- the guarded acceptance environment variables are explicitly supplied.
local Bootstrap = {}

local SLOT_VARIABLE = "PICTURE_SHOP_ACCEPTANCE_HOST_SLOT"
local IDENTITY_VARIABLE = "PICTURE_SHOP_ACCEPTANCE_IDENTITY"
local SCREEN_VARIABLE = "PICTURE_SHOP_ACCEPTANCE_HOST_SCREEN"
local IDENTITY_PREFIX = "the-picture-shop-acceptance-"

local function value(getenv, name)
    if type(getenv) ~= "function" then return nil end
    local ok, result = pcall(getenv, name)
    if not ok or type(result) ~= "string" or result == "" then return nil end
    return result
end

function Bootstrap.plan(options)
    options = type(options) == "table" and options or {}
    local getenv = options.getenv
    local slotText = value(getenv, SLOT_VARIABLE)
    if not slotText then return nil end

    if options.osName ~= "Windows" then
        return nil, "The acceptance host bootstrap is restricted to Windows."
    end
    if not slotText:match("^[1-3]$") then
        return nil, "The acceptance host slot must be 1, 2, or 3."
    end

    local identity = value(getenv, IDENTITY_VARIABLE)
    if not identity or #identity > 80
        or identity:sub(1, #IDENTITY_PREFIX) ~= IDENTITY_PREFIX
        or not identity:match("^[a-z0-9%-]+$")
    then
        return nil, "The acceptance save identity is missing or outside its guarded namespace."
    end

    local screen = value(getenv, SCREEN_VARIABLE)
    if screen and screen ~= "computer" then
        return nil, "The acceptance host screen must be computer."
    end

    return {
        slot = tonumber(slotText),
        identity = identity,
        playerName = "Acceptance Worker",
        screen = screen,
    }
end

Bootstrap.SLOT_VARIABLE = SLOT_VARIABLE
Bootstrap.IDENTITY_VARIABLE = IDENTITY_VARIABLE
Bootstrap.SCREEN_VARIABLE = SCREEN_VARIABLE
Bootstrap.IDENTITY_PREFIX = IDENTITY_PREFIX

return Bootstrap
