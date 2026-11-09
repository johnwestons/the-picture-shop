local Codec=require('src.net.codec')
local Town=require('src.commute.town')

local limits={maxBytes=8*1024*1024,maxDepth=16,maxEntries=500000,maxStringBytes=4096,maxNumberBytes=32}
local configString,prefix=...
local progressChannel=love.thread.getChannel(prefix..'-progress')
local resultChannel=love.thread.getChannel(prefix..'-result')
local cancelChannel=love.thread.getChannel(prefix..'-cancel')
local config,configError=Codec.decode(configString,{maxBytes=65536,maxDepth=8,maxEntries=256,maxStringBytes=512,maxNumberBytes=32})
if type(config)~='table' or type(config.seed)~='number' or type(config.island)~='table' then
    resultChannel:push({status='error',error='Could not read town generation settings: '..tostring(configError)})
    return
end

local cancelRequested=false
local function isCancelled()
    if cancelChannel:pop() then cancelRequested=true end
    return cancelRequested
end
local function progress(value,label)
    if isCancelled() then return end
    progressChannel:push({progress=math.max(0,math.min(1,tonumber(value) or 0)),
        label=tostring(label or 'Generating town…')})
end

local town,err=Town.generate(config.seed,{island=config.island,progress=progress,isCancelled=isCancelled})
if isCancelled() then
    resultChannel:push({status='cancelled'})
elseif not town then
    resultChannel:push({status='error',error=tostring(err or 'Could not generate this town.')})
else
    progress(.99,'Finalizing preview data')
    local encoded,encodeError=Codec.encode(town,limits)
    if isCancelled() then resultChannel:push({status='cancelled'})
    elseif encoded then resultChannel:push({status='complete',town=encoded})
    else resultChannel:push({status='error',error='Could not transfer the generated town: '..tostring(encodeError)}) end
end
