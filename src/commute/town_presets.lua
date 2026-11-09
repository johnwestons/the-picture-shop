-- Local named towns contain the complete generated plan, not just its seed.
local Town=require('src.commute.town')
local Codec=require('src.net.codec')
local Presets={FILE='town-presets.dat',MAX_ITEMS=48,MAX_NAME=28}
-- A generated plan includes the frozen height grid (~100KB); leave room for
-- all 48 normal towns while bounding malformed files before parsing.
local limits={maxBytes=8*1024*1024,maxDepth=16,maxEntries=500000,maxStringBytes=256,maxNumberBytes=32}
Presets.MAX_BYTES=limits.maxBytes
function Presets.cleanName(value)
    if type(value)~='string' then return '' end
    return (value:gsub('[^%w%s%.%-]',' '):gsub('%s+',' '):match('^%s*(.-)%s*$') or '')
        :sub(1,Presets.MAX_NAME):gsub('%s+$','')
end
local function filesystem() return love and love.filesystem end
local function validate(items)
    if type(items)~='table' or #items>Presets.MAX_ITEMS then return nil,'Invalid saved town list.' end
    local result,names={},{}
    for key in pairs(items) do
        if type(key)~='number' or key%1~=0 or key<1 or key>#items then return nil,'Invalid saved town list.' end
    end
    for _,item in ipairs(items) do
        if type(item)~='table' or type(item.name)~='string' then return nil,'Invalid saved town.' end
        local name=Presets.cleanName(item.name)
        if name=='' or name~=item.name or names[name:lower()] then return nil,'Invalid saved town name.' end
        if type(item.town)~='table' then return nil,'Invalid saved town layout.' end
        local copied,town=pcall(Town.copy,item.town)
        if not copied or not Town.valid(town) then return nil,'Invalid saved town layout.' end
        names[name:lower()]=true;result[#result+1]={name=name,town=town}
    end
    return result
end
function Presets.load()
    local files=filesystem()
    if not files then return {},'Saved towns are unavailable.' end
    local inspected,info=pcall(files.getInfo,Presets.FILE)
    if not inspected then return {},'Could not inspect saved towns.' end
    if not info then return {} end
    if not info.size or info.size>limits.maxBytes then return {},'Saved town file is too large.' end
    local read,source=pcall(files.read,Presets.FILE,limits.maxBytes+1)
    if not read or type(source)~='string' then return {},'Could not read saved towns.' end
    local data=Codec.decode(source,limits)
    if type(data)~='table' or data.version~=1 then return {},'Saved town file is damaged.' end
    local items,err=validate(data.items)
    return items or {},err
end
function Presets.write(items)
    local files=filesystem()
    if not files then return false,'Saved towns are unavailable.' end
    local normalized,err=validate(items)
    if not normalized then return false,err end
    local source;source,err=Codec.encode({version=1,items=normalized},limits)
    if not source then return false,'Town presets exceed storage limits: '..tostring(err) end
    local called,ok,reason=pcall(files.write,Presets.FILE,source)
    if not called or not ok then return false,'Could not save towns: '..tostring(reason or ok) end
    local read,actual=pcall(files.read,Presets.FILE,limits.maxBytes+1)
    if not read or actual~=source then return false,'Could not verify saved towns. Try saving again.' end
    return true
end
function Presets.upsert(items,item)
    if type(item)~='table' then return nil,'Choose a town to save.' end
    local name=Presets.cleanName(item.name)
    if name=='' then return nil,'Enter a name for this town.' end
    if not Town.valid(item.town) then return nil,'Generate a valid town before saving it.' end
    local result,err=validate(items or {})
    if not result then return nil,err end
    local replacement={name=name,town=Town.copy(item.town)}
    local found
    for index,existing in ipairs(result) do
        if existing.name:lower()==name:lower() then result[index]=replacement;found=true;break end
    end
    if not found then
        if #result>=Presets.MAX_ITEMS then return nil,'Delete a saved town before adding another.' end
        result[#result+1]=replacement
    end
    local ok;ok,err=Presets.write(result)
    return ok and result or nil,err
end
function Presets.remove(items,index)
    local result,err=validate(items or {})
    if not result then return nil,err end
    if not result[index] then return nil,'Choose a saved town first.' end
    table.remove(result,index)
    local ok;ok,err=Presets.write(result)
    return ok and result or nil,err
end
return Presets
