-- Checkpoint values keep their existing Lua-double precision, with explicit
-- little-endian IEEE-754 storage on Windows and Android. No global codec change.
local Codec=require('src.net.codec')
local Wire={MAX_VALUES=64,BYTES_PER_VALUE=8}
local formats={}
for count=1,Wire.MAX_VALUES do formats[count]='<'..string.rep('d',count)end
local function finite(value)
    return type(value)=='number' and value==value and value>=-1e12 and value<=1e12
end
function Wire.pack(values)
    if not Codec.isArray(values) or #values<1 or #values>Wire.MAX_VALUES then return nil,'Invalid checkpoint value count' end
    local data=type(love)=='table' and love.data
    if not data or type(data.pack)~='function' then return nil,'Binary checkpoints are unavailable' end
    local canonical={}
    for i,value in ipairs(values)do
        if not finite(value) then return nil,'Invalid checkpoint value' end
        canonical[i]=value==0 and 0 or value
    end
    local okay,bytes=pcall(data.pack,'string',formats[#canonical],unpack(canonical))
    if not okay or type(bytes)~='string' or #bytes~=#canonical*Wire.BYTES_PER_VALUE then return nil,'Invalid binary checkpoint' end
    return bytes
end
function Wire.unpack(bytes,count)
    if type(count)~='number' or count%1~=0 or count<1 or count>Wire.MAX_VALUES
        or type(bytes)~='string' or #bytes~=count*Wire.BYTES_PER_VALUE then return nil,'Invalid binary checkpoint size' end
    local data=type(love)=='table' and love.data
    if not data or type(data.unpack)~='function' then return nil,'Binary checkpoints are unavailable' end
    local decoded={pcall(data.unpack,formats[count],bytes)}
    if not decoded[1] or decoded[count+2]~=#bytes+1 then return nil,'Invalid binary checkpoint' end
    local values={}
    for i=1,count do
        local value=decoded[i+1]
        -- Zero has one canonical wire representation, matching the text codec.
        if not finite(value) or value==0 and 1/value<0 then return nil,'Invalid binary checkpoint value' end
        values[i]=value
    end
    return Codec.array(values)
end
return Wire
