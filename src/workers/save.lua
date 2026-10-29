require("love.filesystem")
require("love.timer")
require("love.system")
local requests,results=...
local stores={}
while true do
    local job=requests:demand()
    if job.kind=="stop" then break end
    local okay,saved,reason=pcall(function()
        local store=stores[job.directory]
        if not store then
            stores={}
            store=require("src.save_store")(require("src.save_worker_filesystem")(job.directory))
            stores[job.directory]=store
        end
        return store.save(job.slot,job.state,job.world)
    end)
    results:push({directory=job.directory,slot=job.slot,okay=okay and saved==true,
        reason=okay and reason or tostring(saved)})
end
