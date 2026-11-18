-- Only the session's private copy-on-write replication baseline may reuse town
-- validation. Opaque handles cannot be reconstructed from decoded wire data.
-- Gameplay and disk-save tables continue to receive fresh validation each time.
local Shared={}
local contexts=setmetatable({},{__mode='k'})
function Shared.new()
    local handle={}
    contexts[handle]={towns=setmetatable({},{__mode='k'})}
    return handle
end
function Shared.context(handle)
    return type(handle)=='table' and contexts[handle] or nil
end
return Shared
