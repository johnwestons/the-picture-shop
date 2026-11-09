-- Gameplay writes immutable snapshots in a worker; synchronous reads/deletes
-- wait for older writes before touching the same slot files.
local store = require("src.save_store")(love.filesystem)
local writer = require("src.async_save").new(store)
local synchronous = {}
for _,name in ipairs({"save","load","delete","listSlots"}) do
    synchronous[name]=store[name]
    store[name]=function(...)
        local okay,reason=writer:flush()
        if writer:pending() then return nil,reason or "save_busy" end
        return synchronous[name](...)
    end
end
function store.queue(slot,state,world) return writer:queue(slot,state,world) end
function store.poll() return writer:poll() end
function store.flush() return writer:flush() end
function store.pending() return writer:pending() end
function store.shutdown() return writer:shutdown() end
function store.ownsWorker(thread) return writer.threads[thread]==true end
return store
