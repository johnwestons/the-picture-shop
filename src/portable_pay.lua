-- A device-wide receipt book moves host-paid wages into one local shop save.
-- Cumulative receipts and per-save claim markers make reconnects idempotent.
local Codec=require('src.net.codec')
local Pay={FILE='portable-pay-v1.dat'}
local TEMP='portable-pay-v1.dat.tmp'
local limits={maxBytes=32768,maxDepth=5,maxEntries=1024,maxStringBytes=64,maxNumberBytes=32}
local sequence=0
local function integer(n,low,high)
    return type(n)=='number' and n==math.floor(n) and n>=low and n<=high
end
function Pay.validShopId(id)
    return type(id)=='string' and #id==32 and id:match('^[0-9a-f]+$')~=nil
end
function Pay.newShopId()
    sequence=sequence+1
    local source=tostring(os.time())..':'..tostring(os.clock())..':'..sequence..':'..tostring({})
    if love and love.data and love.data.hash then
        return love.data.encode('string','hex',love.data.hash('sha256',source)):sub(1,32)
    end
    local a=(os.time()+sequence*104729)%2147483647
    return ('%08x%08x%08x%08x'):format(a,math.floor(os.clock()*1e6)%2147483647,sequence,104729)
end
function Pay.validClaims(claims)
    if claims==nil then return true end
    if type(claims)~='table' then return false end
    local count=0
    for id,paid in pairs(claims) do
        count=count+1
        if count>256 or not Pay.validShopId(id) or not integer(paid,0,1e12) then return false end
    end
    return true
end
local function valid(book)
    if type(book)~='table' or book.version~=1 or type(book.sources)~='table'
        or type(book.claimed)~='table' then return false end
    if not integer(book.sequence,0,1e12) then return false end
    if book.credentialHash~=nil and not require('src.resident_credentials').valid(book.credentialHash) then return false end
    if not Pay.validClaims(book.sources) or not Pay.validClaims(book.claimed) then return false end
    if next(book.sources)~=nil and book.credentialHash==nil then return false end
    for id,paid in pairs(book.claimed) do
        if paid>(book.sources[id] or 0) then return false end
    end
    return true
end
function Pay.load()
    if not love or not love.filesystem then return nil,'Portable pay storage is unavailable.' end
    local function candidate(path)
        if not love.filesystem.getInfo(path) then return nil end
        local source=love.filesystem.read(path)
        local book=type(source)=='string' and Codec.decode(source,limits)
        return valid(book) and book or nil
    end
    local primary,temporary=candidate(Pay.FILE),candidate(TEMP)
    if primary and temporary then return primary.sequence>=temporary.sequence and primary or temporary end
    if primary or temporary then return primary or temporary end
    if love.filesystem.getInfo(Pay.FILE) or love.filesystem.getInfo(TEMP) then
        return nil,'The portable pay receipt book is damaged.'
    end
    return {version=1,sequence=0,sources={},claimed={}}
end
local function write(book)
    if not valid(book) then return false,'Invalid portable pay receipts.' end
    book.sequence=book.sequence+1
    local source,reason=Codec.encode(book,limits)
    if not source then return false,reason end
    local okay,errorMessage=love.filesystem.write(TEMP,source)
    if not okay or love.filesystem.read(TEMP)~=source then
        return false,errorMessage or 'Portable pay could not be verified.'
    end
    if love.filesystem.getInfo(Pay.FILE) and not love.filesystem.remove(Pay.FILE) then
        return false,'Portable pay could not replace the prior receipt.'
    end
    local slash=package.config:sub(1,1)
    local root=love.filesystem.getSaveDirectory()
    local renamed=os.rename(root..slash..TEMP,root..slash..Pay.FILE)
    if not renamed then
        okay,errorMessage=love.filesystem.write(Pay.FILE,source)
        if not okay or love.filesystem.read(Pay.FILE)~=source then
            return false,errorMessage or 'Portable pay could not be verified.'
        end
        love.filesystem.remove(TEMP)
    end
    return true
end
function Pay.record(shopId,paidCents,token)
    if not Pay.validShopId(shopId) or not integer(paidCents,0,1e12)
        or not require('src.resident_credentials').valid(token) then return false,'Invalid wage receipt.' end
    local digest=love.data.encode('string','hex',love.data.hash('sha256',token))
    local book,reason=Pay.load()
    if not book then return false,reason end
    if book.credentialHash and book.credentialHash~=digest then return false,'Portable wages belong to a different resident identity.' end
    if paidCents<=(book.sources[shopId] or 0) then return true,false end
    book.credentialHash=digest
    book.sources[shopId]=paidCents
    local okay,errorMessage=write(book)
    return okay,okay and true or errorMessage
end
function Pay.recordSnapshot(state,residentId,token)
    if not require('src.resident_credentials').valid(token) then return false,'Resident identity is unavailable.' end
    local home=state and state.home
    local resident=home and home.residents and home.residents[residentId]
    local digest=love.data.encode('string','hex',love.data.hash('sha256',token))
    if not resident or resident.credentialHash~=digest then return false,'Wage receipt identity does not match.' end
    return Pay.record(home.shopId,resident.wagePaidCents or 0,token)
end
-- Reconcile claims saved in any slot before giving another slot the balance.
-- If a process ended between saving a slot and finalizing the receipt book,
-- that slot's marker proves the transfer already happened.
function Pay.claim(state,save,saveCurrent)
    local book,reason=Pay.load()
    if not book then return false,reason end
    if next(book.sources)==nil then return true,0 end
    local token,identityError=require('src.resident_credentials').get()
    if not token then return false,identityError end
    local digest=love.data.encode('string','hex',love.data.hash('sha256',token))
    if digest~=book.credentialHash then return false,'Portable wages belong to a different resident identity.' end
    local changed=false
    for slot=1,3 do
        local payload=save.load(slot)
        local claims=payload and payload.state and payload.state.home and payload.state.home.portableClaims
        if Pay.validClaims(claims) then
            for id,paid in pairs(claims or {}) do
                if paid>(book.claimed[id] or 0) and paid<=(book.sources[id] or 0) then
                    book.claimed[id]=paid;changed=true
                end
            end
        end
    end
    if changed then
        local okay,errorMessage=write(book)
        if not okay then return false,errorMessage end
    end
    local claims=state.home.portableClaims or {}
    local added=0
    for id,paid in pairs(book.sources) do
        local claimed=book.claimed[id] or 0
        if paid>claimed then
            added=added+paid-claimed
            claims[id]=paid
        end
    end
    if added==0 then return true,0 end
    if state.home.balanceCents+added>1e12 then return false,'Household balance is full.' end
    state.home.portableClaims=claims
    state.home.balanceCents=state.home.balanceCents+added
    state.home.revision=state.home.revision+1
    local saved,errorMessage=saveCurrent(true)
    if not saved then return false,errorMessage or 'Could not save imported wages.' end
    for id,paid in pairs(claims) do
        if paid>(book.claimed[id] or 0) then book.claimed[id]=paid end
    end
    -- A saved slot marker recovers this final write if it is interrupted.
    write(book)
    return true,added
end
return Pay
