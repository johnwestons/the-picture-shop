-- PNG decoding runs off-thread. GPU transfer remains on the render thread,
-- capped at one 2 MiB strip per update and one decoded image in flight.
local Loader={enabled=false}
local Upload=require("src.texture_upload")
local queue,states={},{}
local thread,requests,results,active
local uploading,uploadPath
local ownedThreads=setmetatable({}, {__mode="k"})
local readyBytes=0
local MAX_READY_BYTES=32*1024*1024
local function start()
    if thread then return end
    requests,results=love.thread.newChannel(),love.thread.newChannel()
    thread=love.thread.newThread("src/workers/image_decode.lua")
    ownedThreads[thread]=true
    thread:start(requests,results)
end
local function dispatch()
    if active or uploading or #queue==0 or readyBytes>=MAX_READY_BYTES then return end
    start()
    active=table.remove(queue,1)
    requests:push({kind="decode",path=active})
end
function Loader.setEnabled(value) Loader.enabled=value==true end
function Loader.request(path)
    if states[path] then return end
    states[path]={requestedAt=love.timer.getTime()}
    -- Reopening a screen can reuse an identical decode already in flight.
    if active==path then return end
    queue[#queue+1]=path
    dispatch()
end
function Loader.cancel(path)
    if uploadPath==path then uploading:release();uploading,uploadPath=nil,nil end
    local record=states[path]
    if record and record.image then record.image:release();readyBytes=readyBytes-record.bytes end
    states[path]=nil
    for index=#queue,1,-1 do if queue[index]==path then table.remove(queue,index) end end
end
function Loader.load(path)
    if not Loader.enabled then
        local okay,image=pcall(love.graphics.newImage,path)
        return okay and image or nil,not okay and tostring(image) or nil
    end
    Loader.request(path)
    local record=states[path]
    if record.image then
        states[path]=nil;readyBytes=readyBytes-record.bytes
        return record.image
    end
    return nil,record.reason or "pending"
end
function Loader.update()
    if not Loader.enabled then return end
    local now=love.timer.getTime()
    for path,record in pairs(states) do
        if record.image and now-record.readyAt>20 then
            record.image:release();readyBytes=readyBytes-record.bytes;states[path]=nil
        end
    end
    if results then
        local result=results:pop()
        if result then
            active=nil
            local record=states[result.path]
            if record then
                if result.data then
                    uploading,uploadPath=Upload.new(result.data),result.path
                else record.reason=result.reason or "Image decoding failed" end
            elseif result.data then result.data:release()
            end
        end
        local reason=thread:getError()
        if reason then
            if active and states[active] then states[active].reason=reason end
            thread,requests,results,active=nil,nil,nil,nil
        end
    end
    if uploading then
        local okay,image=pcall(uploading.step,uploading)
        if not okay then
            uploading:release();states[uploadPath].reason=tostring(image)
            uploading,uploadPath=nil,nil
        elseif image then
            local record=states[uploadPath]
            record.image,record.readyAt=image,now
            record.bytes=image:getWidth()*image:getHeight()*4
            readyBytes=readyBytes+record.bytes
            uploading,uploadPath=nil,nil
        end
    end
    dispatch()
end
function Loader.pending() return active~=nil or uploading~=nil or #queue>0 end
function Loader.readyBytes() return readyBytes end
function Loader.ownsWorker(value) return ownedThreads[value]==true end
function Loader.shutdown()
    if thread then requests:push({kind="stop"});thread:wait() end
    if results then
        local result=results:pop()
        while result do
            if result.data then result.data:release() end
            result=results:pop()
        end
    end
    for _,record in pairs(states) do if record.image then record.image:release() end end
    if uploading then uploading:release();uploading,uploadPath=nil,nil end
    queue,states,readyBytes={}, {}, 0
    thread,requests,results,active=nil,nil,nil,nil
end
return Loader
