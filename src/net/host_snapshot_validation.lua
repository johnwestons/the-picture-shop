-- Mutable host state cannot use the received-baseline identity memo. Retain one
-- detached validated town per session and compare every value before reusing it.
local Town=require('src.commute.town')
local Validation={}
local contexts=setmetatable({},{__mode='k'})

local function equalTown(value,previous)
    local count=0
    local function equal(a,b,depth)
        count=count+1
        if count>150000 or depth>14 or type(a)~=type(b) then return false end
        if type(a)~='table' then return a==b end
        -- Never trust identity, __eq, __index or custom iteration on live state.
        if getmetatable(a)~=nil or getmetatable(b)~=nil then return false end
        local size=0
        for k,v in next,a do
            count=count+1
            if count>150000 or (type(k)~='string' and type(k)~='number')
                or not equal(v,rawget(b,k),depth+1) then return false end
            size=size+1
        end
        for _ in next,b do
            size=size-1
            if size<0 then return false end
        end
        return size==0
    end
    return equal(value,previous,0)
end

function Validation.new()
    local handle={}
    contexts[handle]={}
    return handle
end

function Validation.prepare(handle,town)
    local context=type(handle)=='table' and contexts[handle] or nil
    if not context or town==nil then return nil,true end
    if not context.town or not equalTown(town,context.town) then
        if not Town.valid(town) then return nil,false end
        context.town=Town.copy(town)
    end
    -- A fresh memo lives only for this synchronous normalization pass. Neither
    -- the caller's mutable town nor a normalized result enters the private cache.
    return {towns={[town]=true}},true
end

return Validation
