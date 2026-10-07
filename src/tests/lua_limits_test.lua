-- Compile source without executing it, including every nested function.
-- Leave headroom below LuaJIT's 200 locals / 250 slots / 60 upvalues limits.
local Test = {}
local SLOT_BUDGET, UPVALUE_BUDGET = 180, 45

local function sourceFiles(directory, files)
    local entries = love.filesystem.getDirectoryItems(directory)
    table.sort(entries)
    for _, name in ipairs(entries) do
        local path = directory .. "/" .. name
        local info = love.filesystem.getInfo(path)
        if info and info.type == "directory" then sourceFiles(path, files)
        elseif name:match("%.lua$") then files[#files + 1] = path end
    end
end

local function withinBudget(util, fn)
    local info = util.funcinfo(fn)
    if info.stackslots > SLOT_BUDGET or info.upvalues > UPVALUE_BUDGET then
        return false, string.format("line %d: %d slots, %d upvalues (budgets %d/%d)",
            info.linedefined, info.stackslots, info.upvalues, SLOT_BUDGET, UPVALUE_BUDGET)
    end
    for index = 1, info.gcconsts do
        local child = util.funck(fn, -index)
        if type(child) == "proto" then
            local valid, diagnostic = withinBudget(util, child)
            if not valid then return false, diagnostic end
        end
    end
    return true
end

function Test.run(_, check)
    local util = require("jit.util")
    local files = { "main.lua", "conf.lua" }
    sourceFiles("src", files)
    for _, path in ipairs(files) do
        local chunk, diagnostic = love.filesystem.load(path)
        local valid = chunk ~= nil
        if chunk then valid, diagnostic = withinBudget(util, chunk) end
        check("lua_limits_" .. path:gsub("[^%w]", "_"), valid, diagnostic)
    end
end

return Test
