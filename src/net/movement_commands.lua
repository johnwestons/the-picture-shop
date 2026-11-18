-- Fixed-width movement samples keep two seconds of redundant input below the
-- realtime packet ceiling, including continuously changing analog steering.
local Commands={MAX_FRAMES=120,BYTES_PER_FRAME=3}
function Commands.count(bytes)
    if type(bytes)~='string' or #bytes<3 or #bytes%3~=0 or #bytes>Commands.MAX_FRAMES*3 then return nil end
    for i=1,#bytes,3 do
        local a,b,c=bytes:byte(i,i+2)
        local value=a+b*256+c*65536
        if c>=128 or value%2048>2000 or math.floor(value/2048)%2048>2000 then return nil end
    end
    return #bytes/3
end
function Commands.pack(history,first)
    local result={}
    for i=first or math.max(1,#history-Commands.MAX_FRAMES+1),#history do
        local frame=history[i]
        local x=math.floor(math.max(-1,math.min(1,frame.x))*1000+.5)+1000
        local y=math.floor(math.max(-1,math.min(1,frame.y))*1000+.5)+1000
        local value=x+y*2048+(frame.boost and 4194304 or 0)
        result[#result+1]=string.char(value%256,math.floor(value/256)%256,math.floor(value/65536))
    end
    return table.concat(result)
end
function Commands.unpack(bytes)
    local count=Commands.count(bytes)
    if not count then return nil end
    local result={}
    for i=1,#bytes,3 do
        local a,b,c=bytes:byte(i,i+2)
        local value=a+b*256+c*65536
        result[#result+1]={value%2048-1000,math.floor(value/2048)%2048-1000,math.floor(value/4194304)}
    end
    return result
end
return Commands
