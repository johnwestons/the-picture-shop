-- Private installation credential. Only its digest enters a hosted save or
-- shared snapshot; names and transient network slots are never identities.
local Credentials={}
function Credentials.valid(value)
    return type(value)=="string" and #value==64 and value:match("^[0-9a-f]+$")~=nil
end
function Credentials.get()
    local path="resident-identity-v1.txt"
    if love.filesystem.getInfo(path) then
        local value=love.filesystem.read(path)
        if Credentials.valid(value) then return value end
        return nil,"The saved resident identity is unreadable. Restore that identity to reconnect to your resident."
    end
    local bytes,_,source=require("src.net.secure_random").bytes(32)
    if type(bytes)~="string" or #bytes~=32 then return nil,"Secure resident identity generation is unavailable on this device." end
    local token=love.data.encode("string","hex",bytes)
    if not love.filesystem.write(path,token) or love.filesystem.read(path)~=token then
        return nil,"Could not save this device's resident identity."
    end
    return token,nil,source
end
return Credentials
