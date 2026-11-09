require("love.filesystem")
require("love.image")
local requests,results=...
while true do
    local job=requests:demand()
    if job.kind=="stop" then break end
    local okay,data=pcall(love.image.newImageData,job.path)
    results:push({path=job.path,data=okay and data or nil,reason=not okay and tostring(data) or nil})
end
